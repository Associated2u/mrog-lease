# mrog-lease

A **leased, audited privilege layer for AI agents on a Linux desktop.** Two leases, one
model: the human arms a time-boxed lease with their password; the agent may then do a
narrow, policy-checked set of things; every action is journalled; stopping is free, starting
never is.

```
                 password (sudo / polkit)                    NOPASSWD, inert without a lease
 human ──────► mrog-lease grant 20 --scope t2 ──► /run/mrog/lease.json ◄── mrog-apply write … (agent)
 human ──────► mrog-input-lease grant 10 --scope click ─► /run/mrog/input-lease.json ◄── mrog-input click … (agent)
 human ──────► [STOP] / move the mouse / mrog-input-kill ──► lease destroyed, journal entry
```

It exists because an agent that can run `sudo` can do anything, and an agent that can
type can bypass every tool-level guard by typing into a terminal. Both problems get the
same shape of answer: the capability is granted for minutes, scoped, refused by default,
and visible on screen the whole time (the [notch-pills](https://github.com/Associated2u/notch-pills)
system pill shows an amber or red dot with a countdown, and a STOP capsule).

Built and run on Linux Mint 22 / Cinnamon / X11. **[REVIEW.md](REVIEW.md) is the security
review** — read it before trusting any claim below.

## 1. The root lease — `root/`

| piece | installed as | what |
|---|---|---|
| `mrog-lease` | `/usr/local/sbin`, root-only | `grant <min> [--scope t1\|t2\|shell] [--note]`, `status`, `revoke`. Writes the lease file (root:root 0644 in `/run/mrog`, so the user cannot forge or extend it). 1–240 min; `shell` capped at 60. |
| `mrog-apply` | `/usr/local/sbin`, **the only NOPASSWD binary** (`user ALL=(root) NOPASSWD: /usr/local/sbin/mrog-apply`, no wildcards) | Refuses everything unless a live lease of sufficient scope exists. Verbs below. |
| `mrog` | `/usr/local/bin` | the user-side driver: `mrog unit … / pkg … / diff / write / revert / run / journal / status`; leaves the session id in `~/.config/mrog/sid` for the journal (sudo strips the env). |
| `policy.conf` | `/etc/mrog` | the allow/deny lists. **Every pattern quoted** — the unquoted first version expanded globs at source time, so the never-touch list only covered files that already existed. |

**Scopes.** `t1` = restart/enable allow-listed units, install allow-listed packages.
`t2` = + write allow-listed config paths. `shell` = + arbitrary root via `mrog run`, journalled
with full output to `/var/log/mrog/run/<ts>.log`, against a deny-list that is honestly a
**tripwire** for the catastrophic (`mkfs`, `rm -rf /`, `visudo`, key paths), not a sandbox — the
control is the password-armed, time-boxed lease and the journal.

**`write` is the careful verb.** `mrog diff <target> <staged>` prints a unified diff and a
**confirm token** (hash of that diff). `mrog write <target> <staged> <token>` then: needs `t2`
· canonicalises the path (`realpath -m` — see REVIEW.md finding 1) · refuses the never-touch
list (`/etc/sudoers*`, `/etc/shadow`, `/boot/*`, `/etc/mrog/*`, the mrog binaries, WireGuard,
`~/.ssh`, the vault, the Claude hook and settings) · requires the allow-list · requires the
token to match the diff *as it is now* (a changed file since `diff` = refused) · runs a
validator where one exists (`systemd-analyze verify`, `sshd -t`) · snapshots the old file to
`/var/backups/` · `install`s with the original mode · `etckeeper commit`s · journals to
`/var/log/mrog/changes.jsonl` with caller and session id. `revert` restores from `/etc`'s git
HEAD.

`unlock-shell.sh` and `remove-apt-nopasswd.sh` are the two one-paste hardening steps that
made the lease *enforcing*: quoting the policy, and removing a passwordless-apt rule that was
functionally passwordless-everything (`dpkg -i` runs maintainer scripts as root;
`apt-get -o APT::Update::Pre-Invoke::=cmd update` runs `cmd` as root with no package at all).

## 2. The input lease — `input/`

An agent that can synthesise keyboard and mouse events (XTEST — any X11 client can) is
outside every tool-level hook. `mrog-input` is the only sanctioned way, and it is gated
harder than root:

| gate | what trips it |
|---|---|
| **lease** | no live `/run/mrog/input-lease.json` (root-owned; `mrog-input-lease grant`, **max 15 min**) → every mutating verb refuses. `where`, `window`, `status`, `shot`, `audit` work without one |
| **panic** | `$XDG_RUNTIME_DIR/mrog/input-panic` exists → `INPUT HALTED` |
| **scope** | `click` / `type` / `both` — `type` and `key` refused under a click-only lease |
| **window denylist** | per-event check of the focused window's class and title (`MROG_INPUT_DENY_CLASS`, `_TITLE` in `input-policy.conf`) — terminals, password prompts, the browser profile that holds logins |
| **human-motion abort** | the pointer moved **≥ 212 px** (1.5 in at this panel's 141 dpi; the recompute formula is in the policy) without us → panic latched, lease **destroyed** |
| **event budget** | 400 events per lease, ≥ 60 ms apart |
| **probe budget** | 8 denied clicks in one lease → panic (a denylist hit is otherwise free to retry window by window) |

Middle-click pastes PRIMARY into whatever has focus, and setting PRIMARY needs no lease — so
a click lease *already* grants text entry. That is deliberate; what was wrong was that the
audit could not tell a paste from a click. Now every button-2 event records the pasted
length and a prefix (`MROG_INPUT_LOG_PASTE=prefix|length|off`).

Verbs: `move x y`, `click [btn]`, `moveclick`, `type "…"`, `key …`, `where`, `window`,
`status`, `shot`, `audit`, `revoke`. Dual audit: `/var/log/mrog/input/events.jsonl` and
journald. `aim.sh` is the helper an agent uses to find a target before it clicks.

**Stopping is free, starting is not.** `mrog-input-kill` is the second and last NOPASSWD
binary: root-only, **takes no arguments**, deletes exactly `/run/mrog/input-lease.json`.
The pill's red dot, the STOP capsule, the motion abort and `revoke` all call it. Granting a
new lease always costs the password.

`docs/MROG_INPUT_PROOF_2026-09-04.md` is the proof run: **every gate driven to fail on its own
stated failure class** — no-lease, panic, scope, denied-class, human-motion — with a granted
lease genuinely permitting.

## 3. The desktop front door — `ui/`

`com.mrog.lease.policy` (polkit, `auth_admin`, `allow_any`/`allow_inactive` = **no**) →
`mrog-lease-ui input|root|revoke [minutes] [scope]`. This is what the notch dot calls via
`pkexec`: a password dialog, then a lease, with ceilings lower than the CLI's (input 15,
root 60, shell 30).

## 4. The model-state switch — `legal/`

Fleet-specific but the same pattern: `com.mrog.legal.policy` → `mrog-legal-ui`, which after
polkit authentication drops **back to the user** and runs their `~/bin/dreamzs-legal-mode
--toggle-bg` — the password is the approval gate for a fleet-wide model swap, not a
privilege. On the two macOS hosts `dreamzs-swap-daemon` does the swap; its sudoers rule
grants **three verbs** (`legal|normal|check`) of one root-owned script, never `cp`/`plutil`/
`launchctl` with free arguments, and the daemon refuses to run a script that is not root-owned
and non-user-writable. The pill's green/amber/red dot reads its state file.

## 5. The Claude Code hook — `hooks/`

`guard-bash.sh` is a `PreToolUse` hook for the Bash tool: logs every command, blocks the
handful that are irreversible, secret-leaking, or route around the lease (T3: `sudoers`,
key files, the vault, `rm -rf /`). It is a keyword tripwire with four hard-won lessons in it
(quoted text is data, a command is a sequence, a comment is not a command, a heredoc body is
data). It is **not** a boundary — the lease and `mrog-apply`'s policy are — and it will refuse
a read-only command that merely *mentions* a guarded word (it did twice during the review).
`guard-cases.txt` + `test-guard.sh` are its regression suite.

## What is enforcing, and what is not

| control | enforcing? | why |
|---|---|---|
| root lease | **yes** | lease file root-owned; the only NOPASSWD binaries are argument-checked and inert without it; apt NOPASSWD removed; `/etc/apt` root-only; `secure_path` + `env_reset` |
| never-touch list | **yes, after REVIEW.md finding 1 is installed** | canonicalised match |
| input lease | **yes** | root-owned lease; kill is delete-only |
| panic file | no — user-removable | it is a *convenience* brake; the motion abort destroys the root-owned lease as well, which is the real stop |
| shell deny-list | no | tripwire by design |
| guard-bash hook | no | sees Bash tool text, not keystrokes; keyword-level |

## Install

Each installer is one `sudo bash` paste and validates its own sudoers fragment with
`visudo -c` before it lands (a failed check removes the rule): `root/install-mrog.sh`,
`input/install-mrog-input.sh`, `input/install-mrog-input-kill.sh`, `hooks/install-claude-guard.sh`.
The polkit policies go to `/usr/share/polkit-1/actions/`, the UIs to `/usr/local/sbin`.
`docs/AGENTIC_SHELL_HANDBOOK.md` is the full plan and the rulings behind it.

## Standalone: the root lease on its own

The root-lease half is also published as
[agent-control-shell](https://github.com/Associated2u/agent-control-shell) — the same
`root/` files (same sources, both exports of `~/mrog`) plus a **tray icon**, an `acs`
CLI and panel integrations (Waybar, Polybar, Cinnamon, a cairo-pill class). This repo stays
whole: it is where the input lease, the polkit UIs, the legal switch and the review live.

## This repo

This is the public export of the maintainer's working tree. Machine and account names in
the docs and comments are placeholders (`hub`, `gpubox`, `mini`, `hubuser`…); the incidents,
measurements and the review are real. The macOS model-swap daemon and its sudoers rule are
fleet-specific and not included. Fixes arrive as PRs here and are ported back.

MIT — see [LICENSE](LICENSE).
