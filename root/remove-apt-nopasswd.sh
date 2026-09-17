#!/usr/bin/env bash
# ============================================================================
#  Remove the passwordless-apt rule, safely and reversibly.
#
#  WHY: NOPASSWD on apt / apt-get / dpkg is functionally NOPASSWD on
#  everything. `dpkg -i` runs maintainer scripts as root, and
#  `apt-get -o APT::Update::Pre-Invoke::=<cmd> update` runs <cmd> as root with
#  no package involved at all. While that rule exists, every lease in the mrog
#  design is advisory: an agent wanting root would simply go around it.
#
#  WHAT SURVIVES: the 50-mrog-agentic rule is NOT touched. mrog-apply keeps its
#  NOPASSWD entry - it is inert without a live lease, which is the point - and
#  password sudo keeps working via your membership of the `sudo` group.
#
#  WHAT CHANGES: `sudo apt install ...` will ask for your password again.
#
#    sudo bash ~/mrog/remove-apt-nopasswd.sh
#
#  Undo (the backup path is printed at the end):
#    sudo cp -a /root/<backup> /etc/sudoers.d/99-chris-apt && sudo visudo -c
# ============================================================================
set -uo pipefail
[[ $EUID -eq 0 ]] || { echo "run me as root: sudo bash $0"; exit 1; }

D=/etc/sudoers.d
TARGET="$D/99-chris-apt"
KEEP="50-mrog-agentic"
STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP="/root/99-chris-apt.removed-$STAMP"

echo "== BEFORE =="
if [[ ! -f $TARGET ]]; then
    echo "  $TARGET does not exist - nothing to remove."
    echo "  Current drop-ins: $(ls "$D" | tr '\n' ' ')"
    echo
    # Do NOT exit here. The point of this script is the QUESTION "is there a
    # passwordless path to root", not the one filename. Exiting early skipped
    # the audit below and left that question unanswered.
    echo "== every remaining NOPASSWD rule =="
    grep -rn "NOPASSWD" /etc/sudoers "$D" 2>/dev/null | sed 's/^/      /' || echo "      none"
    echo
    echo "== what each non-mrog rule actually lets you run =="
    for f in "$D"/*; do
        b=$(basename "$f")
        [[ $b == "$KEEP" || $b == README ]] && continue
        grep -q NOPASSWD "$f" 2>/dev/null || continue
        echo "  --- $b ---"
        sed 's/^/      /' "$f"
    done
    echo
    echo "Judge each one the same way: does it reach a binary that can run"
    echo "arbitrary code as root (a package manager, an interpreter, anything"
    echo "taking a -o/--exec/--command option)? If yes, it is a root bypass."
    exit 0
fi
echo "  $TARGET contains:"
sed 's/^/      /' "$TARGET"
echo
echo "  all drop-ins: $(ls "$D" | tr '\n' ' ')"

# --- is anything relying on passwordless apt? ------------------------------
echo
echo "== things that might now start prompting =="
hits=0
UHOME="$(getent passwd "${SUDO_USER:-root}" | cut -d: -f6)"
MR="${MROG_ROOT:-$UHOME/mrog}"
for d in "$UHOME/bin" "$MR" /etc/cron.d /etc/cron.daily; do
    [[ -d $d ]] || continue
    while IFS= read -r line; do
        echo "      $line"; hits=1
    done < <(grep -rlE 'sudo +(apt|apt-get|dpkg)' "$d" 2>/dev/null)
done
(( hits )) || echo "      nothing found - no script here relies on it"

# --- back up, remove, validate ---------------------------------------------
echo
echo "== REMOVING =="
cp -a "$TARGET" "$BACKUP" || { echo "  backup FAILED - nothing removed"; exit 1; }
chmod 600 "$BACKUP"
echo "  backed up to $BACKUP"
rm -f "$TARGET"
echo "  removed $TARGET"

if visudo -c >/dev/null 2>&1; then
    echo "  visudo -c: OK"
else
    echo "  🔴 visudo -c FAILED - restoring and aborting"
    cp -a "$BACKUP" "$TARGET"
    visudo -c
    exit 1
fi

# --- the rule that must survive --------------------------------------------
echo
echo "== the agentic-shell rule must still be there =="
if [[ -f "$D/$KEEP" ]]; then
    sed 's/^/      /' "$D/$KEEP"
else
    echo "      🔴 $KEEP IS MISSING - mrog-apply will now prompt. Reinstall with:"
    echo "         sudo bash $MR/install-mrog.sh"
fi

# --- anything else still passwordless? -------------------------------------
echo
echo "== any remaining NOPASSWD rules anywhere =="
grep -rn "NOPASSWD" /etc/sudoers "$D" 2>/dev/null | sed 's/^/      /' || echo "      none"

command -v etckeeper >/dev/null && etckeeper commit "remove passwordless apt/dpkg rule" >/dev/null 2>&1

cat <<DONE

== NOW PROVE IT ==
Run these as chris, in this order. The first clears the sudo credential cache -
without it you will not see a prompt and will think nothing changed.

  1.  sudo -k
  2.  sudo -n apt-get --version        -> must FAIL: "a password is required"
  3.  sudo -n /usr/local/sbin/mrog-apply    -> must still RUN (no password)
  4.  sudo apt-get --version           -> asks for your password now. Correct.

Backup: $BACKUP
Undo:   sudo cp -a $BACKUP $TARGET && sudo visudo -c
DONE
