# MIR Compatibility Audit Summary

- Audit dir: `C:\Projects\Factorio\more-infinite-research\artifacts\ecosystem-qualification\available-closures`
- Load results: 7
- Manual results: 7
- Failure groups: 10
- Unexpected failure groups: 10
- Expected failure groups: 0
- Profile candidates: 0
- Compatibility observations: 0
- Distinct missing/incompatible dependencies: 3

## Groups By Kind

| Kind | Count |
| --- | ---: |
| dependency_resolution_failure | 3 |
| load_failure | 1 |
| no_audit_rows | 6 |

## Failure Groups

- `FG0001` `dependency_resolution_failure` expected=`False` scenario=`local-2-1-krastorio-space-exploration` mod=`space-exploration-graphics-2` stream=`` recipe=`` reason=`dependency-resolution`
- `FG0002` `dependency_resolution_failure` expected=`False` scenario=`local-2-1-krastorio-space-exploration` mod=`space-exploration-menu-simulations` stream=`` recipe=`` reason=`dependency-resolution`
- `FG0003` `dependency_resolution_failure` expected=`False` scenario=`local-2-1-krastorio-space-exploration` mod=`space-exploration-postprocess` stream=`` recipe=`` reason=`dependency-resolution`
- `FG0004` `no_audit_rows` expected=`False` scenario=`local-2-1-crucible-rigor-exact-dist` mod=`planet-crucible` stream=`` recipe=`` reason=`audit_rows_empty`
- `FG0005` `no_audit_rows` expected=`False` scenario=`local-2-1-space-age-planet-cluster` mod=`Cerys-Moon-of-Fulgora` stream=`` recipe=`` reason=`audit_rows_empty`
- `FG0006` `no_audit_rows` expected=`False` scenario=`local-2-1-aai-representative-extensions` mod=`aai-containers` stream=`` recipe=`` reason=`audit_rows_empty`
- `FG0007` `no_audit_rows` expected=`False` scenario=`local-2-1-bz-suite-space-age` mod=`bzcarbon` stream=`` recipe=`` reason=`audit_rows_empty`
- `FG0008` `no_audit_rows` expected=`False` scenario=`local-2-1-krastorio-base` mod=`Krastorio2` stream=`` recipe=`` reason=`audit_rows_empty`
- `FG0009` `load_failure` expected=`False` scenario=`local-2-1-krastorio-space-exploration` mod=`Krastorio2` stream=`` recipe=`` reason=`exit_code=1`
- `FG0010` `no_audit_rows` expected=`False` scenario=`local-2-1-bob-suite` mod=`bobassembly` stream=`` recipe=`` reason=`audit_rows_empty`
