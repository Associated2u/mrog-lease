#!/usr/bin/env bash
# ============================================================================
#  Round 3 - the unlock. Four pieces, one paste.
#
#  1. /etc/mrog/policy.conf  ⚠ SECURITY FIX
#     The patterns were unquoted, so bash expanded them when the file was
#     sourced. MROG_WRITE_ALLOW became 285 literal paths that happened to exist
#     (which is why no new file could be created), and - far worse - MROG_DENY
#     became 56 literal paths, so the never-touch list did NOT cover anything
#     that did not already exist. A new /etc/sudoers.d/99-anything was never
#     denied. Now quoted, and verified in a sandbox: a write to a NEW file
#     under a denied prefix is refused, a NEW file in an allowed prefix passes.
#
#  2. /usr/local/sbin/mrog-lease   new `shell` scope, capped at 60 minutes
#  3. /usr/local/sbin/mrog-apply   new `run` verb: arbitrary root inside a
#     shell lease, refused by a command denylist, every invocation journalled
#     with its full output in /var/log/mrog/run/
#  4. /usr/local/bin/mrog          `mrog run ...` passthrough
#
#  Plus the Timeshift ship job (weekly, never creates a snapshot).
#
#    sudo bash ~/mrog/unlock-shell.sh
# ============================================================================
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run me as root: sudo bash $0"; exit 1; }
STAMP=$(date +%Y%m%d-%H%M)
S="${MROG_ROOT:-$(getent passwd "${SUDO_USER:-root}" | cut -d: -f6)/mrog}/staged"

for f in /tmp/mrog-apply-s3 /tmp/mrog-lease-s3 /tmp/mrog-s3 "$S/timeshift-ship"; do
    [[ -f $f ]] || { echo "missing staged file: $f"; exit 1; }
    bash -n "$f" || exit 1
    command -v shellcheck >/dev/null && { shellcheck -S error "$f" || exit 1; }
done
bash -n "$S/policy.conf" || exit 1
echo "== every staged file passes bash -n and shellcheck"

echo "== policy.conf: the patterns that were silently glob-expanded"
diff -u /etc/mrog/policy.conf "$S/policy.conf" | sed -n '4,50p' || true

for pair in "/etc/mrog/policy.conf:$S/policy.conf:0644" \
            "/usr/local/sbin/mrog-apply:/tmp/mrog-apply-s3:0755" \
            "/usr/local/sbin/mrog-lease:/tmp/mrog-lease-s3:0755" \
            "/usr/local/bin/mrog:/tmp/mrog-s3:0755" \
            "/usr/local/bin/timeshift-ship:$S/timeshift-ship:0755"; do
    dst=${pair%%:*}; rest=${pair#*:}; src=${rest%%:*}; mode=${rest##*:}
    [[ -f $dst ]] && cp -a "$dst" "/var/backups/$(basename "$dst").$STAMP"
    install -o root -g root -m "$mode" "$src" "$dst"
    echo "   installed $dst"
done

install -o root -g root -m 0644 "$S/timeshift-ship.service" /etc/systemd/system/timeshift-ship.service
install -o root -g root -m 0644 "$S/timeshift-ship.timer"   /etc/systemd/system/timeshift-ship.timer
systemd-analyze verify /etc/systemd/system/timeshift-ship.service || true
systemctl daemon-reload
systemctl enable --now timeshift-ship.timer >/dev/null 2>&1 && echo "   timeshift-ship.timer enabled (Sundays 04:10)"

mkdir -p /var/log/mrog/run
chown root:adm /var/log/mrog/run
chmod 750 /var/log/mrog/run

command -v etckeeper >/dev/null && etckeeper commit "mrog: policy glob fix, shell lease, run verb, timeshift-ship" >/dev/null 2>&1 || true

cat <<'DONE'

Unlocked. Prove it in this order:

  mrog run whoami                          -> refused, no live lease
  sudo mrog-lease grant 30 --scope shell   -> your password, self-expiring, max 60 min
  mrog run whoami                          -> root
  mrog audit 5                             -> every attempt, with the session id
  ls /var/log/mrog/run/                    -> the full output of each command
  mrog unlease                             -> ends it early

  sudo timeshift-ship --dry-run            -> size of the first ship, nothing sent
DONE
