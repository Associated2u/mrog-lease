#!/usr/bin/env bash
# Installs the PreToolUse Bash guard into ~/.claude/settings.json. No root.
#   bash ~/mrog/install-claude-guard.sh
set -euo pipefail
S="$HOME/.claude/settings.json"
P="${MROG_ROOT:-$HOME/mrog}/claude-settings-proposed.json"
python3 -c "import json;json.load(open('$P'))" || { echo "proposed file is not valid JSON"; exit 1; }
cp -a "$S" "$S.bak-$(date +%Y%m%d-%H%M)"
# The proposed file is written against /home/USER; the hook path must be absolute and yours.
python3 - "$P" "$S" "$HOME" <<'PY'
import sys
src, dst, home = sys.argv[1:4]
open(dst, "w").write(open(src).read().replace("/home/USER", home))
PY
python3 -c "import json;d=json.load(open('$S'));print('installed. hooks:',list(d.get('hooks',{})),' deny rules:',len(d.get('permissions',{}).get('deny',[])))"
echo "Backup of the old file is beside it (.bak-*)."
echo "Hooks load at session start - restart the Claude Code session for it to take effect."
echo "To undo: cp \$(ls -t $S.bak-* | head -1) $S"
