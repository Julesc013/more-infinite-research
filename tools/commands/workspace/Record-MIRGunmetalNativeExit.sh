#!/usr/bin/bash
set -eu

# Run as a reviewed packet's systemd ExecStopPost command. The main process
# outcome is supplied by the manager for this exact invocation.
test "$#" -eq 1
[[ $1 =~ ^[A-F0-9]{64}$ ]]
[[ ${INVOCATION_ID:-} =~ ^[0-9a-f]{32}$ ]]
printf 'MIR_NATIVE_SYSTEMD_EXIT_V1 invocation=%s packet=%s result=%s code=%s status=%s\n' \
    "$INVOCATION_ID" "$1" "${SERVICE_RESULT:-unknown}" "${EXIT_CODE:-unknown}" "${EXIT_STATUS:-unknown}"
