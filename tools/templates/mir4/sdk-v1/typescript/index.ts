export type Availability = { status: "available" | "unavailable"; reason: string; evidence: string[] };
export type ApiSurface = "continuity-bundle"|"host-manifest"|"observation"|"profile"|"proof"|"query"|"release"|"target-provider-abi"|"tooling";
export interface Mir4ApiResponse<T=unknown> {
  kind:"MIR4ApiResponseV1"; schema:1; surface:ApiSurface;
  target:{id:string;factorio_line:string;transport:string}; versions:{source:string;distribution:string};
  capabilities:string[]; availability:Availability;
  page:{offset:number;limit:number;returned:number;total:number|null;next_cursor:string|null};
  items:T[]; canonicalization:"mir-canonical-json/1"; extensions:Record<string,unknown>; source_identity:unknown;
  package_visible:false; mutation_authorized:false; public_support_claim:false; digest:string;
}
export {
  SdkError, parse, canonicalize, digest, validate, negotiateCapabilities, decodeAvailability,
  boundedPage, compareSnapshots, renderDiagnostic, validateExtension, verifyManifest,
  verifyArchive, runConformance
} from "./index.mjs";
