#!/usr/bin/env bash
# ============================================================================
#  Installs agent keyboard/mouse control, leased.
#
#  What it grants:  NOTHING new at root. mrog-input runs as chris with no
#                   setuid and no root - on X11, XTEST input needs neither.
#                   No new sudoers rule is added by this script at all.
#  The approval gate: /usr/local/sbin/mrog-input-lease is root-only and is
#                   reached through your normal password sudo. Without a live
#                   lease, mrog-input refuses every mutating verb.
#
#    sudo bash ~/mrog/input/install-mrog-input.sh
#
#  To remove all of it:
#    sudo rm -f /usr/local/sbin/mrog-input-lease /usr/local/bin/mrog-input \
#               /etc/mrog/input-policy.conf
#    sudo rm -rf /var/log/mrog/input
# ============================================================================
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run me as root: sudo bash $0"; exit 1; }
SRC="${MROG_ROOT:-$(getent passwd "${SUDO_USER:-root}" | cut -d: -f6)/mrog}/input"
[[ -d $SRC ]] || { echo "no mrog tree at $SRC (set MROG_ROOT)"; exit 1; }
OWNER=chris

command -v xdotool >/dev/null || {
  echo "xdotool is not installed - mrog-input cannot work without it."
  echo "  apt install xdotool"
  exit 1
}

install -o root -g root -m 0755 "$SRC/mrog-input-lease" /usr/local/sbin/mrog-input-lease
install -o root -g root -m 0755 "$SRC/mrog-input"       /usr/local/bin/mrog-input
install -d -o root -g root -m 0755 /etc/mrog
[[ -f /etc/mrog/input-policy.conf ]] ||
  install -o root -g root -m 0644 "$SRC/input-policy.conf" /etc/mrog/input-policy.conf

# The event log is written by mrog-input running unprivileged, so chris owns
# it. journald (logger -t mrog-input) is the copy chris cannot quietly edit -
# that is the one to trust in an audit.
install -d -o "$OWNER" -g adm -m 0750 /var/log/mrog/input
touch /var/log/mrog/input/events.jsonl
chown "$OWNER":adm /var/log/mrog/input/events.jsonl
chmod 0640 /var/log/mrog/input/events.jsonl

# The policy file is sourced by bash. An unquoted pattern in it silently
# empties the deny list, which is exactly what happened to policy.conf on
# 2026-09-03 - so refuse to finish if any pattern is bare.
if grep -nE '^\s*"?[A-Z_]+=\(' -A6 /etc/mrog/input-policy.conf |
   grep -E '^\s*[^#"[:space:]]*\*' | grep -qv '"'; then
  echo "REFUSING: /etc/mrog/input-policy.conf contains an UNQUOTED glob pattern."
  echo "Quote every pattern, then re-run."
  exit 1
fi

command -v etckeeper >/dev/null && etckeeper commit "install mrog-input leased input control" >/dev/null 2>&1 || true

cat <<'DONE'

Installed. Nothing is armed yet - prove it, in this order:

  1. It refuses with no lease:
       mrog-input move 900 500          -> REFUSED (no-lease)

  2. Read-only verbs work anyway:
       mrog-input where                 -> pointer x y
       mrog-input window                -> focused window class + title
       mrog-input shot                  -> writes a PNG, prints the path

  3. Arm it (asks for your password), then watch the notch dot go RED:
       sudo mrog-input-lease grant 5 --scope click --note "proving it"
       mrog-input moveclick 960 600     -> works

  4. Scope really is separate:
       mrog-input type hello            -> REFUSED (scope-is-click-need-type)

  5. The window denylist really fires - focus a terminal, then:
       mrog-input click                 -> REFUSED (denied-class)

  6. The kill switch needs no password:
       mrog-input revoke                -> input halted
       mrog-input move 900 500          -> REFUSED (panic)

  7. Everything above is on the record, twice:
       mrog-input audit
       journalctl -t mrog-input -n 30

Drive it to fail on its own stated failure class before trusting it green.
DONE
