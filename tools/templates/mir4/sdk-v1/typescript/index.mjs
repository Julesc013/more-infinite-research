import { createHash } from "node:crypto";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve, sep } from "node:path";

const SURFACES = new Set(["continuity-bundle","host-manifest","observation","profile","proof","query","release","target-provider-abi","tooling"]);
const REQUIRED = ["availability","canonicalization","capabilities","digest","extensions","items","kind","mutation_authorized","package_visible","page","public_support_claim","schema","source_identity","surface","target","versions"].sort();
const encoder = new TextEncoder();

export class SdkError extends Error {
  constructor(code) { super(code); this.code = code; }
}

function normalize(value, depth = 0) {
  if (depth > 64) throw new SdkError("mir4-canon-depth");
  if (value === null || typeof value === "boolean") return value;
  if (typeof value === "string") return value.normalize("NFC");
  if (typeof value === "number") {
    if (!Number.isSafeInteger(value) || Object.is(value, -0)) throw new SdkError("mir4-canon-unsupported-number");
    return value;
  }
  if (Array.isArray(value)) return value.map((child) => normalize(child, depth + 1));
  if (typeof value !== "object") throw new SdkError("mir4-canon-invalid-json");
  const result = {};
  const seen = new Set();
  for (const rawKey of Object.keys(value).sort()) {
    const key = rawKey.normalize("NFC");
    if (seen.has(key)) throw new SdkError("mir4-canon-unicode-key-collision");
    seen.add(key);
    result[key] = normalize(value[rawKey], depth + 1);
  }
  return result;
}

export function parse(rawJson) {
  if (rawJson.charCodeAt(0) === 0xfeff) throw new SdkError("mir4-canon-utf8-bom");
  try { return normalize(JSON.parse(rawJson)); }
  catch (error) { if (error instanceof SdkError) throw error; throw new SdkError("mir4-canon-invalid-json"); }
}
export function canonicalize(value) { return JSON.stringify(normalize(value)); }
export function digest(value) {
  const material = Object.fromEntries(Object.entries(value).filter(([key]) => key !== "digest"));
  const prefix = "mir-canonical-json/1\0mir4:api-response-v1\0";
  return "sha256:" + createHash("sha256").update(prefix, "utf8").update(canonicalize(material), "utf8").digest("hex");
}
function ordinalSet(values, code) {
  if (!Array.isArray(values)) throw new SdkError(code);
  const expected = [...new Set(values)].sort();
  if (expected.length !== values.length || expected.some((value, index) => value !== values[index])) throw new SdkError(code);
}
export function validate(value) {
  if (!value || typeof value !== "object" || Array.isArray(value) || JSON.stringify(Object.keys(value).sort()) !== JSON.stringify(REQUIRED) || value.kind !== "MIR4ApiResponseV1" || value.schema !== 1) throw new SdkError("mir4-api-v1-schema");
  if (!SURFACES.has(value.surface)) throw new SdkError("mir4-api-v1-surface");
  if (!value.target || !/^f[0-9]{3}$/.test(value.target.id) || !/^[0-9]+\.[0-9]+$/.test(value.target.factorio_line) || !value.target.transport) throw new SdkError("mir4-api-v1-target");
  if (!value.versions?.source || !value.versions?.distribution) throw new SdkError("mir4-api-v1-version");
  if (value.canonicalization !== "mir-canonical-json/1") throw new SdkError("mir4-api-v1-canonicalization");
  if (value.package_visible !== false || value.mutation_authorized !== false || value.public_support_claim !== false) throw new SdkError("mir4-api-v1-authority-boundary");
  if (!Array.isArray(value.capabilities) || value.capabilities.length > 128) throw new SdkError("mir4-api-v1-capability-cardinality");
  ordinalSet(value.capabilities, "mir4-api-v1-capability-order");
  if (value.capabilities.some((item) => !/^[a-z][a-z0-9]*(?:[.-][a-z0-9]+)*$/.test(item))) throw new SdkError("mir4-api-v1-capability");
  const availability = value.availability;
  if (!availability || !["available","unavailable"].includes(availability.status) || !availability.reason || !Array.isArray(availability.evidence)) throw new SdkError("mir4-api-v1-availability");
  ordinalSet(availability.evidence, "mir4-api-v1-evidence-order");
  const page = value.page;
  if (!page || !Array.isArray(value.items) || !Number.isSafeInteger(page.offset) || !Number.isSafeInteger(page.limit) || !Number.isSafeInteger(page.returned) || page.offset < 0 || page.limit < 1 || page.limit > 128 || page.returned < 0 || page.returned > page.limit) throw new SdkError("mir4-api-v1-page");
  if (page.returned !== value.items.length) throw new SdkError("mir4-api-v1-returned-count");
  if (page.total !== null && (!Number.isSafeInteger(page.total) || page.total < 0 || page.offset + page.returned > page.total)) throw new SdkError("mir4-api-v1-page");
  if (page.next_cursor !== null && !/^[0-9]+$/.test(page.next_cursor)) throw new SdkError("mir4-api-v1-cursor");
  if (availability.status === "unavailable" && (page.total !== null || page.returned !== 0 || value.items.length !== 0 || page.next_cursor !== null)) throw new SdkError("mir4-api-v1-unavailable-is-not-zero");
  if (!value.extensions || Array.isArray(value.extensions) || Object.keys(value.extensions).length > 32) throw new SdkError("mir4-api-v1-extension-cardinality");
  if (Object.keys(value.extensions).some((key) => !/^[a-z][a-z0-9-]*(\.[a-z][a-z0-9-]*)+$/.test(key))) throw new SdkError("mir4-api-v1-extension-namespace");
  if (value.digest !== digest(value)) throw new SdkError("mir4-api-v1-digest");
  return value;
}
export function negotiateCapabilities(value, requested = [], required = []) {
  const offered = [...validate(value).capabilities], request = requested.length ? requested : offered;
  const selected = [...new Set(request.filter((item) => offered.includes(item)))].sort();
  const missing = [...new Set(required.filter((item) => !offered.includes(item)))].sort();
  if (missing.length) throw new SdkError("mir4-api-v1-capability-required");
  return { offered, selected, missing: [] };
}
export function decodeAvailability(value) { const availability = structuredClone(validate(value).availability); return { available: availability.status === "available", ...availability }; }
export function boundedPage(value, expectedCursor = null) {
  const response = validate(value);
  if (expectedCursor !== null && expectedCursor !== String(response.page.offset)) throw new SdkError("mir4-api-v1-cursor-mismatch");
  return { items: structuredClone(response.items), ...structuredClone(response.page) };
}
export function compareSnapshots(before, after) {
  const left = validate(before), right = validate(after);
  if (left.surface !== right.surface || left.target.id !== right.target.id) throw new SdkError("mir4-api-v1-snapshot-identity");
  const itemsChanged = canonicalize(left.items) !== canonicalize(right.items);
  return { equal: !itemsChanged && left.digest === right.digest, before_digest: left.digest, after_digest: right.digest, items_changed: itemsChanged };
}
export async function renderDiagnostic(diagnostic, registryPath = new URL("../diagnostics.json", import.meta.url)) {
  const registry = JSON.parse(await readFile(registryPath, "utf8"));
  if (!registry.diagnostics.some((row) => row.code === diagnostic.code)) throw new SdkError("mir4-api-v1-diagnostic-code");
  return `[${diagnostic.code}] ${diagnostic.path || "$"} ${diagnostic.message || ""}`.trim();
}
export function validateExtension(extension) {
  const required = ["canonicalization","digest","extension_id","extension_version","fragments","kind","namespace","schema","targets"].sort();
  if (!extension || JSON.stringify(Object.keys(extension).sort()) !== JSON.stringify(required) || extension.kind !== "MIR4ExtensionEnvelopeV1" || extension.schema !== 1 || extension.canonicalization !== "mir-canonical-json/1") throw new SdkError("mir4-mep-v1-schema");
  const forbidden = new Set(["callback","callbacks","compiler_context","data_raw","executor","prototype","prototype_write","safety_kernel","safety_kernel_override"]);
  const scan = (child) => { if (child && typeof child === "object") for (const [key, value] of Object.entries(child)) { if (forbidden.has(key)) throw new SdkError("mir4-mep-v1-forbidden-field"); scan(value); } };
  scan(extension);
  const material = Object.fromEntries(Object.entries(extension).filter(([key]) => key !== "digest"));
  const expected = "sha256:" + createHash("sha256").update("mir-canonical-json/1\0mir4:extension-envelope-v1\0", "utf8").update(canonicalize(material), "utf8").digest("hex");
  if (extension.digest !== expected) throw new SdkError("mir4-mep-v1-digest");
  return extension;
}
export async function verifyManifest(manifest, root) {
  if (!Array.isArray(manifest.files) || !manifest.files.length) throw new SdkError("mir4-api-v1-manifest-empty");
  const base = resolve(root), prefix = base + sep, seen = new Set();
  for (const row of manifest.files) {
    const relative = String(row.path || "").replaceAll("\\", "/");
    if (!relative || relative.startsWith("/") || relative.includes(":") || relative.split("/").includes("..") || seen.has(relative)) throw new SdkError("mir4-api-v1-manifest-path");
    seen.add(relative);
    const path = resolve(base, relative);
    if (!path.startsWith(prefix)) throw new SdkError("mir4-api-v1-manifest-path");
    const payload = await readFile(path);
    if (row.bytes !== payload.length || row.sha256 !== createHash("sha256").update(payload).digest("hex")) throw new SdkError("mir4-api-v1-manifest-digest");
  }
  return true;
}
export async function verifyArchive(archive, extract) {
  const scratch = await mkdtemp(join(tmpdir(), "mir4-sdk-v1-"));
  try {
    await extract(archive, scratch);
    const { readdir } = await import("node:fs/promises");
    const roots = (await readdir(scratch, { withFileTypes: true })).filter((item) => item.isDirectory());
    if (roots.length !== 1) throw new SdkError("mir4-api-v1-archive-root");
    const root = join(scratch, roots[0].name);
    return verifyManifest(JSON.parse(await readFile(join(root, "manifest.json"), "utf8")), root);
  } finally { await rm(scratch, { recursive: true, force: true }); }
}
export async function runConformance(path) {
  const corpus = JSON.parse(await readFile(path, "utf8")), accepted = [], rejected = [], failures = [], digests = {};
  for (const test of corpus.positive) {
    try { const value = validate(parse(test.input_json)); accepted.push(test.id); digests[test.id] = value.digest; if (value.digest !== test.digest || canonicalize(value) !== test.canonical_json) failures.push(test.id + ":identity"); }
    catch (error) { failures.push(test.id + ":" + (error.code || error.message)); }
  }
  for (const test of corpus.negative) {
    try { validate(parse(test.input_json)); failures.push(test.id + ":accepted"); }
    catch (error) { rejected.push(test.id); if ((error.code || error.message) !== test.diagnostic) failures.push(test.id + ":" + (error.code || error.message)); }
  }
  return { schema: 1, kind: "MIR4SdkV1RuntimeConformanceResult", runtime: "node", accepted, rejected, digests, failures, passed: failures.length === 0 };
}

if (process.argv[1] && resolve(process.argv[1]) === resolve(new URL(import.meta.url).pathname.slice(process.platform === "win32" ? 1 : 0))) {
  const index = process.argv.indexOf("--conformance");
  if (index < 0 || !process.argv[index + 1]) throw new SdkError("mir4-sdk-v1-command");
  const result = await runConformance(process.argv[index + 1]);
  process.stdout.write(JSON.stringify(result) + "\n");
  process.exitCode = result.passed ? 0 : 1;
}
