"""Read-only capture of one caller-owned private-X Factorio window.

The governed parent owns admission, displays, clients and phase association.
This module neither focuses a window nor injects input. A completed capture
still needs separate phase/visual review.
"""
import binascii
import hashlib
import os
from pathlib import Path, PurePosixPath
import re
import select
import stat
import struct
import subprocess
import sys
import time
import zlib


XWD_LIMIT_BYTES = 20 * 1024 * 1024
STDERR_LIMIT_BYTES = 256 * 1024


class CaptureError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise CaptureError(message)


def digest(path):
    value = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(block)
    return value.hexdigest().upper()


def linux_path(value):
    return isinstance(value, str) and value.startswith('/') and '\\' not in value \
        and '\0' not in value and '..' not in PurePosixPath(value).parts \
        and str(PurePosixPath(value)) == value


def validate_spec(spec, binding, helper):
    fields = {'schema', 'kind', 'role', 'process_id', 'process_start_utc', 'engine_sha256',
              'client_width', 'client_height', 'workspace', 'output_root', 'name', 'xwd'}
    require(isinstance(spec, dict) and set(spec) == fields, 'capture spec fields differ')
    require(type(spec['schema']) is int and spec['schema'] == 1
            and spec['kind'] == 'MIRLinuxLibraryCapturePlanV1', 'capture schema differs')
    require(spec['role'] in ('client-en', 'client-de'), 'capture role differs')
    require(type(spec['process_id']) is int and spec['process_id'] > 0, 'capture PID differs')
    helper.utc(spec['process_start_utc'])
    require(isinstance(spec['engine_sha256'], str)
            and re.fullmatch('[A-F0-9]{64}', spec['engine_sha256']), 'capture engine hash differs')
    require(type(spec['client_width']) is int and type(spec['client_height']) is int
            and (spec['client_width'], spec['client_height']) in ((1280, 720), (2560, 1440)),
            'capture geometry differs')
    helper.validate_binding(spec, binding)
    require(binding['display'] == {'client-en': ':193', 'client-de': ':194'}[spec['role']],
            'capture role/display differs')
    require(linux_path(spec['workspace']) and linux_path(spec['output_root']), 'capture root path differs')
    parent = PurePosixPath(spec['workspace']) / 'build' / 'p'
    output = PurePosixPath(spec['output_root'])
    require(output.is_relative_to(parent) and output != parent, 'capture output escapes workspace build/p')
    require(isinstance(spec['name'], str) and re.fullmatch('[A-Za-z0-9][A-Za-z0-9_-]{0,79}', spec['name']),
            'capture name differs')
    tool = spec['xwd']
    require(isinstance(tool, dict) and set(tool) == {'path', 'bytes', 'sha256'}, 'xwd pin fields differ')
    require(linux_path(tool['path']) and PurePosixPath(tool['path']).name == 'xwd'
            and type(tool['bytes']) is int and tool['bytes'] > 0
            and isinstance(tool['sha256'], str) and re.fullmatch('[A-F0-9]{64}', tool['sha256']),
            'xwd pin differs')
    return spec


def validate_live_paths(spec):
    require(sys.platform == 'linux', 'Linux capture execution required')
    for value in (spec['workspace'], spec['output_root']):
        path = Path(value)
        require(path.is_dir() and path.resolve(strict=True) == path, 'capture directory is absent or aliased')
    root = Path(spec['output_root'])
    require(root.stat().st_uid == os.getuid(), 'capture directory owner differs')
    tool = Path(spec['xwd']['path'])
    info = tool.lstat()
    require(stat.S_ISREG(info.st_mode) and tool.resolve(strict=True) == tool
            and info.st_size == spec['xwd']['bytes'] and digest(tool) == spec['xwd']['sha256'],
            'xwd executable bytes differ')
    paths = {kind: root / (spec['name'] + extension)
             for kind, extension in (('xwd', '.xwd'), ('stderr', '.xwd.stderr'), ('png', '.png'))}
    require(not any(os.path.lexists(path) for path in paths.values()), 'preserve existing capture outputs')
    return paths


def artifact(path):
    path = Path(path)
    return {'path': str(path), 'bytes': path.stat().st_size, 'sha256': digest(path)}


def run_xwd(command, env, paths):
    """Preserve bounded stdout/stderr prefixes even on timeout or refusal."""
    result = {'exit_code': None, 'timed_out': False, 'output_limited': False}
    process = None
    with paths['xwd'].open('xb') as out, paths['stderr'].open('xb') as err:
        try:
            process = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                       stderr=subprocess.PIPE, env=env, close_fds=True)
            channels = {process.stdout.fileno(): (process.stdout, out, XWD_LIMIT_BYTES),
                        process.stderr.fileno(): (process.stderr, err, STDERR_LIMIT_BYTES)}
            counts = {key: 0 for key in channels}
            end = time.monotonic() + 8
            while channels:
                remaining = end - time.monotonic()
                if remaining <= 0:
                    result['timed_out'] = True
                    break
                ready, _, _ = select.select(list(channels), [], [], min(.05, remaining))
                for descriptor in ready:
                    stream, target, maximum = channels[descriptor]
                    chunk = os.read(descriptor, min(8192, maximum + 1 - counts[descriptor]))
                    if not chunk:
                        stream.close()
                        del channels[descriptor]
                        continue
                    target.write(chunk)
                    counts[descriptor] += len(chunk)
                    if counts[descriptor] > maximum:
                        result['output_limited'] = True
                        break
                if result['output_limited']:
                    break
            if process.poll() is None and (result['timed_out'] or result['output_limited']):
                process.kill()
            result['exit_code'] = process.wait(timeout=2)
        finally:
            if process is not None:
                if process.poll() is None:
                    process.kill()
                    process.wait(timeout=2)
                for stream in (process.stdout, process.stderr):
                    if stream is not None and not stream.closed:
                        stream.close()
            for stream in (out, err):
                stream.flush()
                os.fsync(stream.fileno())
    return result


def capture(spec, binding, helper, *, pause=time.sleep, runner=run_xwd, path_check=validate_live_paths):
    receipt = {'kind': 'MIRLinuxLibraryCaptureReceiptV1', 'status': 'refused',
               'native_gui_acceptance': False, 'input_events': 0, 'focus_changes': 0}
    backend = None
    paths = None
    try:
        validate_spec(spec, binding, helper)
        paths = path_check(spec)
        guard, final_hash = helper.process_guard(spec, binding)
        backend = helper.LinuxX11(binding)
        def checked_window():
            guard()
            observed = backend.window(binding, spec)
            require(observed['pid'] == spec['process_id'] and observed['bounds'] == binding['bounds']
                    and observed['mapped'] is True and 'factorio' in observed['title'].casefold(),
                    'owned capture window differs')
        checked_window()
        pause(1.0)
        checked_window()
        command = [spec['xwd']['path'], '-display', binding['display'], '-id', hex(binding['window'])]
        env = dict(os.environ, DISPLAY=binding['display'], XAUTHORITY=binding['xauthority'])
        receipt['xwd_run'] = runner(command, env, paths)
        receipt['raw'] = artifact(paths['xwd'])
        receipt['stderr'] = artifact(paths['stderr'])
        require(receipt['xwd_run']['exit_code'] == 0 and not receipt['xwd_run']['timed_out']
                and not receipt['xwd_run']['output_limited'], 'xwd did not complete within capture bounds')
        checked_window()
        png = xwd_to_png(paths['xwd'].read_bytes(), binding['bounds'])
        with paths['png'].open('xb') as stream:
            stream.write(png)
            stream.flush()
            os.fsync(stream.fileno())
        receipt['png'] = artifact(paths['png'])
        checked_window()
        final_hash()
        receipt.update(status='captured-pending-phase-and-visual-review', role=spec['role'],
                       process_id=spec['process_id'], window=binding['window'], bounds=binding['bounds'],
                       process_identity_checked=True, presentation_wait_seconds=1.0)
    except Exception as error:
        receipt['error'] = str(error)[:512]
        if paths is not None:
            for name in ('xwd', 'stderr', 'png'):
                if paths[name].is_file() and not paths[name].is_symlink():
                    receipt['raw' if name == 'xwd' else name] = artifact(paths[name])
    finally:
        if backend is not None:
            try:
                backend.close()
            except Exception as error:
                receipt['connection_close_error'] = type(error).__name__
                receipt['status'] = 'refused'
    return receipt


# Strict decoder adopted from the retained R04 driver84F41283; only bounds
# are explicit. Earlier capture failures and native results stay unchanged.
def parse_xwd(raw: bytes, bounds) -> tuple[int, int, bytes]:
    require(isinstance(bounds, (tuple, list)) and all(type(value) is int for value in bounds)
            and list(bounds) in ([0, 0, 1280, 720], [0, 0, 2560, 1440]), "xwd bounds differ")
    require(100 <= len(raw) <= XWD_LIMIT_BYTES, "xwd byte size differs")
    candidates = []
    for order in (">", "<"):
        values = struct.unpack(order + "25I", raw[:100])
        if 100 <= values[0] <= 4096 and values[0] <= len(raw):
            candidates.append((order, values))
    require(len(candidates) == 1, "xwd header byte order differs")
    order, fields = candidates[0]
    require(order == ">", "xwd header is not in standard network byte order")
    (header_size, file_version, pixmap_format, depth, width, height, xoffset, byte_order, bitmap_unit,
     bitmap_bit_order, bitmap_pad, bits_per_pixel, bytes_per_line, visual_class, red_mask, green_mask,
     blue_mask, bits_per_rgb, colormap_entries, colors, window_width, window_height, window_x, window_y,
     border_width) = fields
    require(file_version == 7 and pixmap_format == 2 and depth == 24 and bits_per_pixel == 32,
            "xwd format is not 24-depth/32bpp ZPixmap")
    require(byte_order == 0 and red_mask == 0x00FF0000 and green_mask == 0x0000FF00 and blue_mask == 0x000000FF,
            "xwd is not little-endian BGRX")
    require(visual_class in (4, 5), "xwd visual is not TrueColor or DirectColor")
    require(xoffset == 0 and bitmap_unit in (8, 16, 32) and bitmap_pad in (8, 16, 32)
            and bitmap_bit_order in (0, 1) and bits_per_rgb > 0 and colormap_entries >= 0,
            "xwd header facts differ")
    require(width == bounds[2] and height == bounds[3] and window_width == width and window_height == height
            and window_x == bounds[0] and window_y == bounds[1] and border_width == 0,
            "xwd window geometry differs")
    require(bytes_per_line == width * 4 and colors <= 4096, "xwd row or colour table differs")
    pixels_at = header_size + colors * 12
    expected = pixels_at + bytes_per_line * height
    require(expected == len(raw), "xwd payload size differs")
    if visual_class == 5:
        # DirectColor pixels index channel ramps. Decode as BGRX only after
        # proving the complete 8-bit identity ramp, not merely its masks.
        require(bits_per_rgb == 8 and colormap_entries == 256 and colors == 256,
                "xwd DirectColor identity ramp is incomplete")
        seen = set()
        for offset in range(256):
            color = struct.unpack(">IHHHBB", raw[header_size + 12 * offset:header_size + 12 * (offset + 1)])
            pixel, red, green, blue, flags, pad = color
            index = pixel & 255
            require(pixel not in seen and color == (index * 0x010101, index * 257, index * 257, index * 257, 7, 0),
                    "xwd DirectColor ramp is not the declared identity map")
            seen.add(pixel)
    return width, height, raw[pixels_at:]

def png_chunk(kind: bytes, payload: bytes) -> bytes:
    return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", binascii.crc32(kind + payload) & 0xFFFFFFFF)

def xwd_to_png(raw: bytes, bounds) -> bytes:
    width, height, pixels = parse_xwd(raw, bounds)
    rows = bytearray((width * 3 + 1) * height)
    source_at = target_at = 0
    for _ in range(height):
        rows[target_at] = 0
        target_at += 1
        for _ in range(width):
            blue, green, red = pixels[source_at], pixels[source_at + 1], pixels[source_at + 2]
            rows[target_at:target_at + 3] = bytes((red, green, blue))
            source_at += 4
            target_at += 3
    return b"\x89PNG\r\n\x1a\n" + png_chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)) \
        + png_chunk(b"IDAT", zlib.compress(bytes(rows), 9)) + png_chunk(b"IEND", b"")
