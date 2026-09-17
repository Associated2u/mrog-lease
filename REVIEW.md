# Security review — mrog-lease

> Written against the maintainer's private tree: `~/mrog` is its working copy and
> `export.sh` its export tooling; host names are placeholders here. Everything measured is real.

**Date:** 2026-09-17 · **Session:** FLEET-4HY · **Scope:** everything `export.sh` maps: the root
lease (`mrog-lease`, `mrog-apply`, `mrog`, `policy.conf`), the input lease (`mrog-input`,
`mrog-input-lease`, `mrog-input-kill`, `input-policy.conf`), the polkit front doors, the
legal-mode switch and its macOS sudoers, the Claude Code hook. Method: read the code, then
**drive each claim against the live policy on the machine** where that could be done
without a lease. Findings are ordered by severity. Status is as of this commit.

## 1 · 🔴 Never-touch list bypass by path spelling — FIXED AND INSTALLED (2026-09-17)

`mrog-apply` matched the target path **literally** against the deny and allow globs. A
non-canonical spelling of a denied path misses the never-touch entry and still matches the
`/etc/*` allow entry; `install` then writes the literal path, which the kernel resolves to
the real file. Measured against the live `/etc/mrog/policy.conf`:

```
/etc/shadow                never-touch=DENIED  allowlist=ALLOWED  -> blocked
/etc//shadow               never-touch=pass    allowlist=ALLOWED  -> WRITE GOES THROUGH
/etc/../etc/shadow         never-touch=pass    allowlist=ALLOWED  -> WRITE GOES THROUGH
/etc/ssh/../shadow         never-touch=pass    allowlist=ALLOWED  -> WRITE GOES THROUGH
```

So an agent holding a `t2` lease could write `/etc/shadow` or drop a file into
`/etc/sudoers.d/` — root persistence, which is exactly what `t2`'s never-touch list exists
to prevent. It needs a `t2` lease first (password-armed), so the blast radius is "an agent
you already trusted with config writes can escalate to permanent root", not "anyone".

**Fix** (`root/mrog-apply`, committed in `~/mrog` as `2503531`): `canon()` = `realpath -m`,
applied to the target in `diff`, `write` and `revert` **before** any policy decision; the
note `a -> b` is printed to stderr when the spelling changed. Proven on the same inputs:
all three now resolve to `/etc/shadow` → `DENIED`.

🟢 **Install (Chris, one paste; the file is root-owned and on its own never-touch list):**

```bash
sudo install -o root -g root -m 0755 ~/mrog/mrog-apply /usr/local/sbin/mrog-apply && bash ~/mrog-lease/export.sh --check
```

`export.sh --check` must then print `installed copies match their sources`.

**Installed 2026-09-17; verified by `cmp` against the source and by re-driving the matchers on
the installed policy.**

## 2 · 🔴 Source tree was behind the enforcement layer — FIXED

Five installed files differed from their sources in `~/mrog`: `mrog-lease`, `mrog-apply`,
`mrog`, `policy.conf`, `mrog-input`. In every case the **installed** copy was the newer one:
the `shell` scope and `rank()` (ruled 09-03), the quoted policy globs and `MROG_SHELL_DENY`,
the `run` verb, the probe budget and the middle-click paste accounting (09-05). They were
edited in place as root and never backported, so the repo documented a weaker layer than
the one running. This is the same class as the hand-placed `askpill.py` copy in
notch-pills/docs/90-traps.md, on the security layer.

Backported (`~/mrog` commits `d079618`, `5ccbaec`). `export.sh --check` now compares every
installed copy to its source and reports `DRIFT`, so it cannot recur silently.

## 3 · 🟡 `guard-bash.sh` is keyword-level, in both directions

The hook refused two **read-only** commands during this review because the word
`sudoers.d` appeared in them (`ls -la /etc/sudoers.d/` and a bash snippet that only tested
glob matching). Conversely, nothing about it is a boundary: it matches text of Bash tool
calls, so a differently spelled path or an indirect invocation is not seen, and keystrokes
typed through an input lease are never seen at all.

**Recommendation:** keep it, and keep calling it what it is — an audit log plus a tripwire
for the obviously-wrong. The enforcing controls are the root-owned lease files and
`mrog-apply`'s canonicalised policy (finding 1). Do not add the hook to any list of security
guarantees.

## 4 · 🟡 Stopping a root lease still costs a password — RESOLVED (twin installed 2026-09-17)

The design principle is *stopping is free, starting is not*, and `mrog-input-kill`
implements it for the input lease (NOPASSWD, root-only, no arguments, deletes one file).
The root lease has no twin: `mrog-lease revoke` is root-only and not in any NOPASSWD rule,
and the notch dot's revoke goes through `pkexec` (`auth_admin`) — a password dialog on the
way to *stopping* root.

**Recommendation:** a `mrog-lease-kill` mirroring `mrog-input-kill` byte for byte
(delete exactly `/run/mrog/lease.json`, log, no arguments) with its own one-line sudoers
fragment. Then the pill's amber dot and STOP can end a root lease without a dialog.

**Staged 2026-09-17:** `root/mrog-lease-kill` (root-only, no arguments, deletes exactly
`/run/mrog/lease.json` and the shell-warned marker) and `root/install-mrog-lease-kill.sh`
(fragment `52-mrog-lease-kill`, `visudo -cqf` before it lands, removed if the global check
fails). `mrog unlease` and the pill's amber-dot click now try `sudo -n mrog-lease-kill` first
and fall back to the password path, so behaviour is unchanged until the rule exists. The
installer also ships the finding-1 `mrog-apply`, so one paste closes both findings:

```bash
sudo bash ~/mrog/install-mrog-lease-kill.sh && bash ~/mrog/notch/install-notch.sh && bash ~/mrog-lease/export.sh --check
```

`install-notch.sh` restarts the pill so the amber-dot click picks up the new handler;
`export.sh --check` must end with `installed copies match their sources`.

**Installed 2026-09-17.** `mrog unlease` and the pill's amber dot now end a root lease with no
dialog; starting one still costs the password.

## 5 · 🟡 `MROG_SHELL_DENY` is a tripwire, and says so

Glob-matched against the command line: `bash -c "$(base64 -d …)"`, `command visudo`, or a
script on disk all pass. `policy.conf` states this honestly ("a tripwire for the
catastrophic … not a sandbox"). No change; keep the wording, and keep `shell` leases short
(the 60-minute cap and the *watch it* ruling are the actual control).

## 6 · 🟡 Going-public hardcodes — RESOLVED (2026-09-17)

`mrog-apply` reads the session id from `/home/USER/.config/mrog/sid` (a label, passed
through `json.dumps`, so not injectable into the journal — but a fixed home path).
`policy.conf` names `/home/USER/...` in the never-touch list. `dreamzs-swap.sudoers` names
two real accounts (kept out of the public tree). `mrog-legal-ui` runs `~/bin/dreamzs-legal-mode` by
name. All of these are `$SUDO_USER`/`getent`-derivable; do it before any public release.

**Done:** `mrog-apply` exports `MROG_HOME`/`MROG_ROOT` from the caller's passwd entry before
sourcing the policy, `policy.conf` names them, every installer derives the tree from
`SUDO_USER`, and the hook keys on `$HOME`. `mrog-legal-ui`'s script name stays (pkexec strips
the environment; it is a fleet integration shipped as an example).

## 7 · 🟢 What holds up

- **This layer adds exactly two NOPASSWD binaries, neither takes a free path** (the host's other sudoers fragments are Mint's own and were audited 09-04): `mrog-apply`
  (verb-checked, inert without a lease, on its own never-touch list) and `mrog-input-kill`
  (no arguments). Each installer runs `visudo -cqf` on its fragment and removes the rule if
  the global check fails.
- **Lease files are root:root 0644 under `/run/mrog` (0755, root).** The user can read the
  countdown and cannot forge, extend or delete a lease. Expiry is by timestamp in the file,
  checked at every call.
- **Policy is sourced from `/etc/mrog` (root-only), with every glob quoted** — the
  unquoted-glob defect that once made the never-touch list cover only existing files is
  closed and documented in the file itself.
- **`write` is defended in depth:** scope → canonical path → never-touch → allow-list →
  diff-token (the write is refused if the file changed since the diff) → validator → backup
  → `install` with preserved mode → `etckeeper` → journal. `e3b0c442…` (empty diff) is a
  named no-op, not a silent success.
- **polkit actions are `auth_admin` with `allow_any` and `allow_inactive` = no**, and both
  UIs re-check `EUID` and `PKEXEC_UID`. `mrog-legal-ui` deliberately drops back to the
  calling user after authentication.
- **The macOS swap rule grants three verbs of one script**, and the script refuses to run a
  target that is not root-owned and non-user-writable — a strictly narrower surface than
  the `cp`/`plutil`/`launchctl` it wraps.
- **The input layer's gates were each driven to fail on their own failure class** before
  being called working (`docs/MROG_INPUT_PROOF_2026-09-04.md`), and the human-motion abort
  destroys the root-owned lease, so the user-removable panic file is a convenience brake
  and not the last line.
- **`remove-apt-nopasswd.sh`** closed the rule that made every earlier lease advisory.

## Not reviewed

`aim.sh` (target-finding helper; no privilege), `phase0-foundation.sh` and the backup/restore
drill (not in scope), and the macOS side of the swap beyond the sudoers rule and the daemon
source (no access from this review).
