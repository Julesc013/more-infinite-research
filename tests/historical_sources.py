"""Read captured MIR evidence from its original Git objects."""
import hashlib
from pathlib import PurePosixPath
import re
import subprocess


PUBLISHED_COMMIT = "bd9774f323b6eb1561c1d9ff0c91ecc3f7acd1d1"
MIR5_SETTINGS_CAPTURE = "6776d2c749e99a8c75d7cf36470dfc800c85e661"


def read_published_source(repository, path, expected_sha256):
    return _read_source(repository, PUBLISHED_COMMIT, path, expected_sha256)


def read_captured_settings(repository, path, expected_sha256):
    return _read_source(repository, MIR5_SETTINGS_CAPTURE, path, expected_sha256)


def _read_source(repository, revision, path, expected_sha256):
    if (not isinstance(path, str) or not path or "\\" in path or ":" in path
            or PurePosixPath(path).is_absolute()
            or any(part in {"", ".", ".."} for part in path.split("/"))):
        raise ValueError("Historical evidence needs a repository-relative path")
    if re.fullmatch(r"[0-9A-F]{64}", expected_sha256) is None:
        raise ValueError("Historical evidence needs its captured SHA256")
    try:
        data = subprocess.check_output(
            ["git", "-C", str(repository), "show", revision + ":" + path],
            stderr=subprocess.PIPE,
        )
    except subprocess.CalledProcessError as error:
        raise AssertionError(
            f"Historical evidence object unavailable: {revision}:{path}; "
            f"fetch exact commit {revision} before running host controls"
        ) from error
    if hashlib.sha256(data).hexdigest().upper() != expected_sha256:
        raise AssertionError(f"Captured historical evidence changed: {revision}:{path}")
    return data
