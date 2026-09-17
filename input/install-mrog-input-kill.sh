#!/usr/bin/env bash
# ============================================================================
#  Make the kill switch actually hold.
#
#  THE PROBLEM: `mrog-input revoke` wrote a flag into $XDG_RUNTIME_DIR, owned
#  by chris. An agent running as chris could delete that flag and carry on, so
#  the halt was a convenience brake, not a boundary. The human-motion abort
#  inherited the same weakness.
#
#  THE FIX: also destroy the lease itself, which lives in /run/mrog and is
#  owned by root. That needs one new passwordless root entry, so read this
#  before you run it.
#
#  WHAT THE NEW RULE GRANTS: /usr/local/sbin/mrog-input-kill, which takes no
#  arguments, reads no input, and does exactly one thing - delete
#  /run/mrog/input-lease.json. It is 30 lines and you should read it:
#      cat ~/mrog/input/mrog-input-kill
#
#  WHY THAT IS SAFE PASSWORDLESS: it can only ever STOP input. An agent that
#  calls it halts itself. Restarting input still costs your password, because
#  that means granting a new lease and mrog-input-lease is NOT in any NOPASSWD
#  rule. Stopping is free; starting is not.
#
#    sudo bash ~/mrog/input/install-mrog-input-kill.sh
#
#  Undo:
#    sudo rm -f /etc/sudoers.d/51-mrog-input-kill /usr/local/sbin/mrog-input-kill
# ============================================================================
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run me as root: sudo bash $0"; exit 1; }
SRC="${MROG_ROOT:-$(getent passwd "${SUDO_USER:-root}" | cut -d: -f6)/mrog}/input"
[[ -d $SRC ]] || { echo "no mrog tree at $SRC (set MROG_ROOT)"; exit 1; }
RULE=/etc/sudoers.d/51-mrog-input-kill

[[ -f $SRC/mrog-input-kill ]] || { echo "missing $SRC/mrog-input-kill"; exit 1; }

echo "== the binary this rule will expose =="
sed -n '20,40p' "$SRC/mrog-input-kill" | sed 's/^/    /'
echo

install -o root -g root -m 0755 "$SRC/mrog-input-kill" /usr/local/sbin/mrog-input-kill
install -o root -g root -m 0755 "$SRC/mrog-input"      /usr/local/bin/mrog-input
[[ -f /etc/mrog/input-policy.conf ]] &&
  install -o root -g root -m 0644 "$SRC/input-policy.conf" /etc/mrog/input-policy.conf

# One path, no wildcards, validated on a temp file before it can break anything.
TMP=$(mktemp)
cat > "$TMP" <<'RULE'
# Stopping agent input must never need a password - in a panic nobody types a
# command. mrog-input-kill takes no arguments and only deletes the lease file,
# so the worst an attacker gains is the ability to switch input OFF.
# Starting input is NOT here: that is mrog-input-lease, and it costs a password.
chris ALL=(root) NOPASSWD: /usr/local/sbin/mrog-input-kill
RULE
if ! visudo -cqf "$TMP"; then
    echo "syntax check FAILED - nothing installed"; rm -f "$TMP"; exit 1
fi
install -o root -g root -m 0440 "$TMP" "$RULE"
rm -f "$TMP"
if ! visudo -c >/dev/null; then
    rm -f "$RULE"; echo "global check failed - rule removed"; exit 1
fi

command -v etckeeper >/dev/null && etckeeper commit "mrog: delete-only input kill helper" >/dev/null 2>&1 || true

cat <<'DONE'

Installed. Prove it, in this order:

  1. It is passwordless, and honest when nothing is armed:
       sudo -n /usr/local/sbin/mrog-input-kill    -> "no input lease was live"

  2. It refuses to do anything else:
       sudo -n /usr/local/sbin/mrog-input-kill --help   -> "takes no arguments"

  3. The halt now really holds. Arm, then stop, then try to undo the stop:
       sudo mrog-input-lease grant 5 --scope click --note "kill test"
       mrog-input status                 -> scope=click, Ns left
       mrog-input revoke                 -> input halted
       rm -f "$XDG_RUNTIME_DIR/mrog/input-panic"     # delete the soft flag
       mrog-input status                 -> NO LEASE. Deleting the flag no
                                            longer brings input back.
       mrog-input move 900 500           -> REFUSED (no-lease)

  4. Starting still costs your password - that asymmetry is the point:
       sudo -n /usr/local/sbin/mrog-input-lease grant 5 --scope click
         -> a password is required
DONE
