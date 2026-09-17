#!/usr/bin/env bash
# Runs every case in guard-cases.txt through a guard script and reports pass/fail.
#   bash ~/mrog/hooks/test-guard.sh ~/mrog/hooks/guard-bash.v2.sh
#
# In the cases file, a literal \n in the command becomes a real newline, so
# multi-line commands (heredocs) can be tested from a single line.
set -uo pipefail
GUARD="${1:?path to the guard script}"
CASES="${2:-$(dirname "$(readlink -f "$0")")/guard-cases.txt}"
pass=0; fail=0

while IFS='|' read -r want cmd; do
  # Cases are written against /home/USER so they read the same on any machine; the guard
  # itself keys on $HOME, so substitute before running.
  cmd="${cmd//\/home\/USER/$HOME}"
    [[ -z "${want:-}" || "$want" == \#* ]] && continue
    cmd=${cmd//\\n/$'\n'}
    payload=$(CMD="$cmd" python3 -c '
import os, json
print(json.dumps({"session_id":"testcase0000","tool_name":"Bash",
                  "tool_input":{"command":os.environ["CMD"]}}))')
    printf '%s' "$payload" | "$GUARD" >/dev/null 2>&1
    got=$?
    if [[ "$got" == "$want" ]]; then
        pass=$((pass+1))
    else
        fail=$((fail+1)); printf '  FAIL want=%s got=%s  %s\n' "$want" "$got" "${cmd//$'\n'/ · }"
    fi
done < "$CASES"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
