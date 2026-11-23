#!/usr/bin/bash
set -eu

# Run as a reviewed packet's systemd ExecStopPost command. The main process
# outcome is supplied by the manager for this exact invocation.
test "$#" -ge 1
[[ $1 =~ ^[A-F0-9]{64}$ ]]
[[ ${INVOCATION_ID:-} =~ ^[0-9a-f]{32}$ ]]
printf 'MIR_NATIVE_SYSTEMD_EXIT_V1 invocation=%s packet=%s result=%s code=%s status=%s\n' \
    "$INVOCATION_ID" "$1" "${SERVICE_RESULT:-unknown}" "${EXIT_CODE:-unknown}" "${EXIT_STATUS:-unknown}"

# A reviewed GUI launcher can name one or two case roots in execution order.
# Recover the newest display first and keep the original manager outcome.
if (( $# == 1 )); then exit 0; fi
[[ $# -ge 6 && $# -le 7 && $2 == --recover-displays && $3 == /* && $4 == /* && $5 =~ ^[A-F0-9]{64}$ ]]
python=$3
display_cli=$4
module_sha=$5
shift 5
if [[ ${SERVICE_RESULT:-unknown} == success ]]; then exit 0; fi
recovery_status=0
for (( index=$#; index>=1; index-- )); do
    case_root=${!index}
    [[ $case_root == /* && $case_root != / && ! -L $case_root ]]
    for role in en de; do
        plan="$case_root/display-$role-plan.json"
        ready="$case_root/build/p/client-$role/display-ready.json"
        if [[ ! -f $ready ]]; then continue; fi
        [[ -f $plan && ! -L $plan && ! -L $ready ]]
        plan_sha=$(sha256sum -- "$plan")
        ready_sha=$(sha256sum -- "$ready")
        plan_sha=${plan_sha%% *}
        ready_sha=${ready_sha%% *}
        "$python" -I -B "$display_cli" --module-sha256 "$module_sha" --mode recover \
            --checkout "$case_root" --plan "$plan" --plan-sha256 "${plan_sha^^}" --ready-sha256 "${ready_sha^^}" || recovery_status=1
    done
done
exit "$recovery_status"
