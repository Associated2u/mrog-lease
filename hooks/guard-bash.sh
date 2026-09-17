#!/usr/bin/env bash
# PreToolUse hook for Bash.  v2 rev4 - 2026-09-03
#
# Why this exists: log every command an agent runs, and block the handful that
# are irreversible, secret-leaking, or route around the mrog lease.
#
# Four lessons are baked in, every one of them learned by this hook refusing
# legitimate work rather than by it letting something dangerous through:
#   1. Text inside quotes is DATA. Quoted runs are stripped before matching -
#      except inside a shell -c wrapper, where quoted text IS the command.
#   2. A command is a SEQUENCE. It is split into segments (newline ; && || |)
#      and each is matched on its own, so a key path mentioned on line 4 is not
#      "cat a private key" just because line 1 happened to start with cat.
#   3. A COMMENT is not a command.
#   4. A HEREDOC BODY is data - a file being written, or python being piped -
#      unless the body is fed to a shell, in which case it really is a command.
#
# Contract: stdin is the tool-call JSON. exit 0 = allow, exit 2 = block (stderr
# goes back to the model). Any other exit is a non-blocking error, so this file
# failing cannot wedge a session.
#
# NOT airtight, and shouldn't be mistaken for it: it sees only Bash tool calls,
# not Write/Edit, and it sees the command line, not what a script does when run.
# It is a brake on shell execution and an audit log. The boundary is mrog-apply.

# FLEET-V26: no fixed home. MR = the mrog tree, CL = the harness config dir; both appear
# inside regexes below, so a dot in them must be escaped (a bare "." matches anything).
MR="${MROG_ROOT:-$HOME/mrog}"; MR_RE="${MR//./\\.}"
CL="$HOME/.claude";            CL_RE="${CL//./\\.}"
LOG="$CL/bash-audit.log"

IN=$(cat)
CMD=$(printf '%s' "$IN" | python3 -c 'import sys,json
try: print(json.load(sys.stdin).get("tool_input",{}).get("command",""))
except Exception: print("")' 2>/dev/null)
SID=$(printf '%s' "$IN" | python3 -c 'import sys,json
try: print(json.load(sys.stdin).get("session_id","?")[:8])
except Exception: print("?")' 2>/dev/null)
[[ -z $CMD ]] && exit 0

printf '%s  %s  %s\n' "$(date -Is)" "$SID" "$CMD" >> "$LOG" 2>/dev/null

deny() {
    echo "BLOCKED by guard-bash: $1" >&2
    echo "If this is genuinely needed, Chris runs it himself." >&2
    exit 2
}

check() {
    local s="$1"

    # --- irreversible storage operations ---------------------------------
    [[ $s =~ (^|[^[:alnum:]])mkfs(\.|[[:space:]]) ]] && deny "mkfs - filesystem creation"
    [[ $s =~ (^|[^[:alnum:]])(cryptsetup|wipefs|sgdisk|fdisk|parted)[[:space:]] ]] && deny "partition/LUKS tooling"
    [[ $s =~ dd[[:space:]].*of=/dev/(nvme|sd|mmcblk) ]] && deny "dd onto a raw disk"
    [[ $s =~ rm[[:space:]]+(-[[:alnum:]]+[[:space:]]+)*-?[rRf]*[[:space:]]*/([[:space:]]|$) ]] && deny "rm targeting /"
    [[ $s =~ rm[[:space:]].*(-rf|-fr)[[:space:]]+(/etc|/boot|/usr|/var|/home)([[:space:]]|/|$) ]] && deny "recursive delete of a system tree"
    [[ $s =~ (^|[[:space:]])(shred|badblocks)[[:space:]]+/dev/ ]] && deny "destructive write to a device"

    # --- secret exfiltration ---------------------------------------------
    [[ $s =~ ^[[:space:]]*(cat|less|more|head|tail|bat|xxd|od|base64|strings)[[:space:]].*(\.ssh/(id_|.*\.pem)|\.vault/|LINUX_SECRETS) ]] && deny "reading private key material into the transcript"
    [[ $s =~ ^[[:space:]]*(scp|rsync|curl|nc|wget)[[:space:]].*(\.ssh/id_|\.vault/) ]] && deny "sending key material off-machine"

    # --- routing around the lease ----------------------------------------
    if [[ $s =~ (^|[^[:alnum:]_/-])sudo[[:space:]] ]]; then
        [[ $s =~ sudo[[:space:]]+(-n[[:space:]]+)?(/usr/local/sbin/)?mrog(-apply|-lease)?([[:space:]]|$) ]] || \
        [[ $s =~ sudo[[:space:]]+bash[[:space:]]+$MR_RE/ ]] || \
            deny "raw sudo - root goes through mrog-apply under a lease, or through Chris"
    fi
    [[ $s =~ (visudo|/etc/sudoers) ]] && deny "sudoers is Chris-only (T3)"

    # --- the guard and the harness config are not the agent's to edit -----
    if [[ $s =~ ($MR_RE/hooks/|$CL_RE/settings) ]]; then
        [[ $s =~ (^|[^[:alnum:]])(rm|mv|cp|tee|install|sed|truncate|chmod|dd)[[:space:]] ]] && deny "modifying the guard or the harness config - that is Chris's to apply"
        [[ $s =~ \>+[[:space:]]*($MR_RE/hooks/|$CL_RE/settings|~/(mrog/hooks/|\.claude/settings)) ]] && deny "redirecting onto the guard or the harness config - that is Chris's to apply"
    fi
}

# Reduce the command to the parts that are actually commands, then check each.
mapfile -t SEGMENTS < <(CMD="$CMD" python3 -c '
import os, re

c = os.environ["CMD"]

# 1. A heredoc body is data (a file being written, python being piped) unless
#    it is fed to a shell, where it really is a command.
lines = c.split("\n")
kept, i = [], 0
while i < len(lines):
    line = lines[i]
    kept.append(line)
    m = re.search(r"<<-?\s*[\x27\"]?([A-Za-z_][A-Za-z0-9_]*)[\x27\"]?", line)
    if m:
        term = m.group(1)
        feeds_shell = re.search(r"(^|[^\w/-])(bash|sh|zsh|dash|eval)(\s|$)", line) is not None
        i += 1
        while i < len(lines) and lines[i].strip() != term:
            if feeds_shell:
                kept.append(lines[i])
            i += 1
    i += 1
c = "\n".join(kept)

# 2. Split into segments and drop quoted runs and comments from each.
out = []
for p in re.split(r"\n|;|&&|\|\||\||\$\(|`", c):
    p = re.sub(r"\x27[^\x27]*\x27", " ", p)   # single-quoted runs
    p = re.sub(r"\"[^\"]*\"", " ", p)          # double-quoted runs
    p = re.sub(r"(^|\s)#.*$", " ", p)          # comments
    p = p.strip()
    if p:
        out.append(p)
print("\n".join(out))' 2>/dev/null)

if [[ ${#SEGMENTS[@]} -eq 0 ]]; then
    check "$CMD"          # python unavailable: fall back to the whole string
else
    for seg in "${SEGMENTS[@]}"; do check "$seg"; done
fi

# A quoted string is data - unless it is handed to a shell to run.
[[ $CMD =~ (^|[^[:alnum:]_-])(bash|sh|zsh|dash|eval)[[:space:]]+-[a-z]*c([[:space:]]|$) ]] && check "$CMD"

exit 0
