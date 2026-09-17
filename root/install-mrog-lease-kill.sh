#!/usr/bin/env bash
# ============================================================================
#  Make stopping a ROOT lease free, like stopping an input lease already is.
#
#  THE ASYMMETRY THIS RESTORES (REVIEW.md finding 4): mrog-input-kill lets the
#  pill's red dot, the STOP capsule and the motion abort end agent input with
#  no dialog. The root lease had no twin -- `mrog unlease` and the amber dot
#  both asked for a password on the way to STOPPING root.
#
#  WHAT THE NEW RULE GRANTS: /usr/local/sbin/mrog-lease-kill, which takes no
#  arguments, reads no input, and does exactly one thing - delete
#  /run/mrog/lease.json. It is ~30 lines and you should read it:
#      cat ~/mrog/mrog-lease-kill
#
#  WHY THAT IS SAFE PASSWORDLESS: it can only ever END root access. Granting a
#  lease still costs your password; mrog-lease is NOT in any NOPASSWD rule.
#
#    sudo bash ~/mrog/install-mrog-lease-kill.sh
#
#  Undo:
#    sudo rm -f /etc/sudoers.d/52-mrog-lease-kill /usr/local/sbin/mrog-lease-kill
# ============================================================================
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run me as root: sudo bash $0"; exit 1; }
SRC="${MROG_ROOT:-$(getent passwd "${SUDO_USER:-root}" | cut -d: -f6)/mrog}"
[[ -d $SRC ]] || { echo "no mrog tree at $SRC (set MROG_ROOT)"; exit 1; }
RULE=/etc/sudoers.d/52-mrog-lease-kill

[[ -f $SRC/mrog-lease-kill ]] || { echo "missing $SRC/mrog-lease-kill"; exit 1; }

echo "== the binary this rule will expose =="
sed -n '20,34p' "$SRC/mrog-lease-kill" | sed 's/^/    /'
echo

install -o root -g root -m 0755 "$SRC/mrog-lease-kill" /usr/local/sbin/mrog-lease-kill
# The driver and the wrapper learned to prefer the kill helper; ship them too.
install -o root -g root -m 0755 "$SRC/mrog"            /usr/local/bin/mrog
install -o root -g root -m 0755 "$SRC/mrog-apply"      /usr/local/sbin/mrog-apply

# One path, no wildcards, validated on a temp file before it can break anything.
TMP=$(mktemp)
cat > "$TMP" <<'RULE'
# Stopping agent root must never need a password - a brake that asks a
# question is not a brake. mrog-lease-kill takes no arguments and only deletes
# the lease file, so the worst an attacker gains is the ability to switch root
# OFF. Starting is NOT here: that is mrog-lease, and it costs a password.
chris ALL=(root) NOPASSWD: /usr/local/sbin/mrog-lease-kill
RULE
if ! visudo -cqf "$TMP"; then
    echo "syntax check FAILED - nothing installed"; rm -f "$TMP"; exit 1
fi
install -o root -g root -m 0440 "$TMP" "$RULE"
rm -f "$TMP"
if ! visudo -c >/dev/null; then
    rm -f "$RULE"; echo "global check failed - rule removed"; exit 1
fi

command -v etckeeper >/dev/null && etckeeper commit "mrog: delete-only root lease kill helper" >/dev/null 2>&1 || true

cat <<'DONE'

Installed. Prove it, in this order:

  1. Passwordless, and honest when nothing is armed:
       sudo -n /usr/local/sbin/mrog-lease-kill        -> "no root lease was live"

  2. Refuses to do anything else:
       sudo -n /usr/local/sbin/mrog-lease-kill --help -> "takes no arguments"

  3. Arm, then stop without a password:
       sudo mrog-lease grant 5 --scope t1 --note "kill test"
       mrog lease-status                 -> scope=t1, Ns left
       mrog unlease                      -> "root lease destroyed", no prompt
       mrog lease-status                 -> no lease

  4. Starting still costs your password - that asymmetry is the point:
       sudo -n /usr/local/sbin/mrog-lease grant 5   -> a password is required

  5. The pill: with a root lease live, click the amber dot -> it clears with
     no dialog. (Before this, the same click raised polkit.)
DONE
