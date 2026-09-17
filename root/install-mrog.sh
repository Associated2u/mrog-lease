#!/usr/bin/env bash
# ============================================================================
#  Installs the leased-root wrapper. Run ONLY after reading the sudo audit.
#
#  What it grants:  chris may run ONE root binary without a password -
#                   /usr/local/sbin/mrog-apply - which refuses everything
#                   unless a live lease exists.
#  What it does NOT grant: mrog-lease. Granting a lease always costs Chris
#                   his password. That is the approval gate.
#
#    sudo bash ~/mrog/install-mrog.sh
# ============================================================================
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run me as root: sudo bash $0"; exit 1; }
# FLEET-V26: the tree lives in the INVOKING user's home (sudo sets SUDO_USER), or wherever
# MROG_ROOT says. Never a fixed path.
SRC="${MROG_ROOT:-$(getent passwd "${SUDO_USER:-root}" | cut -d: -f6)/mrog}"
[[ -d $SRC ]] || { echo "no mrog tree at $SRC (set MROG_ROOT)"; exit 1; }

install -o root -g root -m 0755 "$SRC/mrog-apply" /usr/local/sbin/mrog-apply
install -o root -g root -m 0755 "$SRC/mrog-lease" /usr/local/sbin/mrog-lease
install -o root -g root -m 0755 "$SRC/mrog"       /usr/local/bin/mrog
install -d -o root -g root -m 0755 /etc/mrog
[[ -f /etc/mrog/policy.conf ]] || install -o root -g root -m 0644 "$SRC/policy.conf" /etc/mrog/policy.conf
install -d -o root -g adm -m 0750 /var/log/mrog
touch /var/log/mrog/changes.jsonl; chown root:adm /var/log/mrog/changes.jsonl; chmod 640 /var/log/mrog/changes.jsonl

# sudoers: exactly one path, no wildcards, validated before it lands
TMP=$(mktemp)
cat > "$TMP" <<'SUDO'
# Agentic shell: one root entry point, inert without a live lease.
# mrog-lease is deliberately NOT here - arming a lease costs Chris his password.
chris ALL=(root) NOPASSWD: /usr/local/sbin/mrog-apply
SUDO
visudo -cqf "$TMP" || { echo "sudoers syntax check FAILED - nothing installed"; rm -f "$TMP"; exit 1; }
install -o root -g root -m 0440 "$TMP" /etc/sudoers.d/50-mrog-agentic
rm -f "$TMP"
visudo -c >/dev/null || { rm -f /etc/sudoers.d/50-mrog-agentic; echo "global sudoers check failed - rule removed"; exit 1; }

command -v etckeeper >/dev/null && etckeeper commit "install mrog leased-root wrapper" >/dev/null 2>&1 || true

cat <<'DONE'

Installed. Nothing is armed yet - prove it:

  mrog snapshot            -> should refuse: "no live lease"
  sudo mrog-lease grant 10 --scope t1      (asks for your password)
  mrog snapshot            -> now works, and expires by itself in 10 minutes
  mrog unlease             -> ends it early
  mrog audit               -> every attempt, allowed or refused, is on the record

To remove all of it:
  sudo rm -f /etc/sudoers.d/50-mrog-agentic /usr/local/sbin/mrog-{apply,lease} /usr/local/bin/mrog
DONE
