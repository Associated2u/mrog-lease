# Laptop — Agentic Shell Handbook

**Status as of 2026-09-03:** **Phase 0 is closed** (drill passed) and **Phase 1 is installed**
(leased root, journal, Bash guard). **Phase 2 is built** — `~/bin/profile`, five profiles, and
`Super+Space` over the same verbs (§8), and the Omarchy parity gap in §0 is closed except for the
shell scope, which is built and waiting on one paste. Phases 3–4 — the lean pass and deeper
customisation — are still design only.
Section 1's table is the ground truth *as measured on 2026-09-02*,
before any of it was fixed; the rulings under it say what changed.

This document is the design, the guardrails, and the order of operations. It is safe to
hand to any agent as context; the unbuilt phases are not an instruction to go do them.

- Machine: laptop (a Linux laptop), Linux Mint 22.3 Zena, Cinnamon 6.6.9, kernel 7.0.0-30
- Author session: LINUX-MN5, 2026-09-02 → 09-03
- Home for this doc: `docs/AGENTIC_SHELL_HANDBOOK.md`

---

## 0. The goal in one sentence

Chris can say *"fix the fan curve / add this systemd unit / change that sysctl"* to an agent,
the agent can actually do it at root level, and **every such change is narrow, logged,
validated before it lands, and revertable in one command** — on a machine that is backed up
well enough that a bad change is boring.

The second goal, in Chris's own words on 2026-09-03: *"I came into this session expecting to have
near similar agentic customization to this OS like I get with Omarchy OS on the Desktop."* That
is the bar. Not "some automation" — parity with the Desktop, without giving up the Cinnamon
session that always works.

### Omarchy parity — measured on both machines, 2026-09-03

| Capability | Omarchy Desktop | laptop today | Gap |
|---|---|---|---|
| Agent CLIs on PATH | **5** — claude, codex, gemini, opencode, crush | ✅ **4 installed 09-03** — codex, gemini, opencode, crush (nvm, user-owned) | closed |
| Shared agent instructions | `~/.claude/CLAUDE.md` → `~/.config/agents/AGENTS.md` | ✅ **same layout 09-03** — one file, symlinked to `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, `~/AGENTS.md` | closed |
| Fleet verb surface | **9+ `fleet-*` commands** — cmd, comms, dash, idle, media, metrics, plan, powersave, production | `mrog` (7 verbs) + `profile` + `leader` + 10 hand-written `~/bin` scripts | less a gap in count than in *reach* — see root |
| Root for agents | password sudo, then a **full shell** | `mrog run` under a shell lease — **built and sandbox-tested, one paste from live** | closing |
| Desktop shell | Hyprland + Quickshell plugins fed by the `fleet-*` scripts | ✅ Cinnamon + 5 profiles + leader menu + **Fleet Status desklet fed by `fleet-status`** | closed |
| Keybindings | Hyprland bind table | ✅ `Super+Space` · `Super+1..5` profiles · `Super+A` audit, written into every profile | closed |

When first measured, two entries inverted the expected story: root was the real gap (a password
bought six units and eleven packages, not a shell), and the agent layer barely existed. Both were
closed the same day — root is one paste from live, the rest is running.

---

## 1. Ground truth as of 2026-09-02 (measured, not assumed)

| Fact | Value | Why it matters |
|---|---|---|
| Root FS | `nvme0n1p2`, ext4, 916 G, 127 G used, **743 G free** | plenty of room; ext4 means Timeshift runs in rsync mode, not btrfs snapshots |
| Second NVMe | `nvme1n1p2`, 477 G NTFS, unmounted | **OUT OF SCOPE** (ruling 2026-09-02): to be wiped, use undecided. Not a backup or sandbox target. |
| RAM / CPU | 23 GiB / 16 threads | a sandbox VM costs nothing meaningful |
| Swap | `/swapfile`, 26 G | hibernation-sized; Secure Boot is off for that reason |
| Boot | 30.6 s total = 16.8 firmware + 3.5 loader + 3.6 kernel + **6.7 userspace** | userspace is already fine; the lean track is about services and RAM, not boot |
| Enabled units | 92 | baseline for drift detection |
| `sudo` | password required; `/etc/sudoers.d/` has `0pwfeedback`, **`99-chris-apt`**, `mintdrivers`, `mintupdate` | `99-chris-apt` may already grant NOPASSWD apt — **must be read before designing tier 1** |
| Timeshift | installed, **`backup_device_uuid` == the root FS UUID**, and **every schedule is `false`** | ⛔ there are no snapshots, and if there were they would live on the disk they protect |
| etckeeper | **not installed** | `/etc` changes are currently untracked and unrevertable |
| shellcheck / ansible | not installed | no static gate on generated scripts |
| Present | docker, flatpak, libvirt/virsh, btrfs-progs, git | sandbox and container options already exist |
| Absent | snap | keep it that way |
| Encryption | **root FS is plain ext4, no dm-crypt** | physical loss = full disclosure; `~/.vault` gpg blobs are the only protected thing |

### The four things that block Phase 1 — and their rulings (2026-09-02)

1. **No snapshots.** Timeshift is installed, aimed at itself, and scheduled never.
   → **Superseded by the ruling of 2026-09-03: Timeshift stays MANUAL.** A scheduler that fires
   in the middle of a laser job or a render is worse than a missing snapshot. (The schedule flags
   `phase0-foundation.sh` set were inert anyway — Timeshift is driven by an hourly cron entry its
   GUI writes, and editing `timeshift.json` creates nothing. A flag flipped with no runner behind
   it: the same failure this session diagnosed on the Desktop, committed here four hours later.)
   What *is* automated is shipping the newest manual snapshot off-machine — see §4.
2. **No `/etc` history.** No etckeeper, no git in `/etc`.
   → `phase0-foundation.sh` installs etckeeper and makes the first commit. **Approved.**
3. ~~**Unknown sudo posture.**~~ **Read 2026-09-03 — and it is the finding of the audit:**
   `/etc/sudoers.d/99-chris-apt` grants
   `chris ALL=(ALL) NOPASSWD: /usr/bin/apt, /usr/bin/apt-get, /usr/bin/dpkg`.
   That is **unrestricted passwordless root**, not a package convenience: `dpkg -i` runs
   maintainer scripts as root, and `apt-get -o APT::Update::Pre-Invoke::=…` runs an arbitrary
   command as root without installing anything. **While that file exists, the lease model is
   decoration** — anything running as `chris` can take root without a lease and without a
   journal line. Recommended fix: delete the file; `mrog pkg add` (leased, allowlisted,
   journalled) covers the legitimate use, and mintupdate keeps its own narrow entries.
4. **No off-machine copy of this machine's own state.**
   → restic to `/data/share/backups/laptop-restic`, matching the existing `omarchy-restic`
   convention on the share (see §4).

---

## 2. Trust model — be honest about what it buys

`chris` is in the `sudo` group. Any agent running as `chris` with the password can do
anything. **This design is not a containment boundary. It is a friction-and-audit boundary
against a careless agent, not a malicious one.** Say that out loud so nobody builds on a
false assumption later.

What it does buy: unattended root is narrow and enumerable, deliberate root is still one
password away, and *every* root change leaves a diff, a log line, and a rollback point.

### Tiers

| Tier | What | Root? | Gate |
|---|---|---|---|
| **T0 — Recon** | read anything not secret: `systemctl status`, `journalctl`, `lsblk`, config reads, `apt list` | no | none |
| **T1 — Allowlisted verbs** | restart *named* units, `apt install` from a pinned list, powerprofile/thermal knobs, mount/unmount named targets | NOPASSWD, wrapper only | **live `t1` lease** + argument on the allowlist + journal |
| **T2 — Config writes** | edit files under `/etc`, install a new systemd unit, sysctl, udev | NOPASSWD via wrapper | **live `t2` lease** + confirm-token matching the reviewed diff + validator + `/etc` git commit + journal |
| **T3 — Human only** | partitions, LUKS, `fstab` device lines, bootloader install, firmware/BIOS, user accounts, `sudoers`, `~/.ssh`, `~/.vault`, anything in `LINUX_SECRETS.tgz.gpg` | Chris types the password | agents may *propose a diff*, never apply |

The T3 list is the fleet's existing "single-holder" doctrine applied to the OS.

### Approval and lease — the ruling (2026-09-02)

> *"NOPASSWD is approval only and lease timeout."*

NOPASSWD exists, and it is **inert**. `chris ALL=(root) NOPASSWD: /usr/local/sbin/mrog-apply`
is the entire grant, and `mrog-apply` refuses every mutating verb unless a live lease sits in
`/run/mrog/lease.json`. Only `mrog-lease` writes that file, and `mrog-lease` is **deliberately
not in the sudoers rule** — arming it costs Chris his password. That is the approval gate.

```
sudo mrog-lease grant 20 --scope t2 --note "fan curve work"   # Chris, password, self-expiring
mrog apply /etc/... /tmp/staged <confirm-token>               # agent, no password, inside the window
mrog unlease                                                  # or just wait for it to lapse
```

Properties worth keeping:

- **Time-boxed.** 1–240 minutes, and the lease lives in `/run` (tmpfs) so a reboot ends it.
- **Scoped.** A `t1` lease cannot perform a `t2` write; the refusal is journalled.
- **Confirm-token.** `mrog diff` prints a hash of the exact diff; `mrog apply` refuses unless
  the token still matches. What was reviewed is what lands, or nothing lands.
- **No-ops are refused** (exit 10) rather than written — the empty-diff hash `e3b0c442…` is
  explicitly special-cased, because on this fleet that hash has already been mistaken for success.
- **Every attempt is journalled**, allowed or refused, with caller and SID.
- Verified in a sandbox before install: no-lease, wrong-scope, expired-lease, denylisted target,
  outside-allowlist, wrong token, no-op, and a `bash -n` failure all refuse; valid writes apply,
  commit to `/etc` git, and journal.

### The shell scope — ruled in 2026-09-03

> *"Yes to mrog"* — the answer to whether agents get a real root shell.

`mrog-lease grant <n> --scope shell` (max 60 minutes) unlocks `mrog run <command…>`: an
arbitrary root command, refused by a command denylist, with **the whole command line and its
complete output** written to `/var/log/mrog/run/<epoch>.log` and a journal line pointing at it.
On the first run of each lease it reports how old the newest Timeshift restore point is — it
does **not** take one, because snapshots are manual by ruling.

Say the honest thing about the denylist: against a real root shell it is a tripwire for the
catastrophic (`mkfs`, `rm -rf /`, key reads, sudoers, rewriting the wrapper), not a sandbox. The
actual controls are that Chris armed a time-boxed lease with his password, and that every
command is on the record with its output.

### ⚠ The policy file was pattern-free for its whole first day

`MROG_DENY` and `MROG_WRITE_ALLOW` were written unquoted, so **bash expanded the globs when the
file was sourced**. `MROG_WRITE_ALLOW` became 285 literal paths that happened to exist — which
is why no new file could ever be created through the leased path — and `MROG_DENY` became 56
literal paths, meaning **the never-touch list did not cover anything that did not already
exist**. A new `/etc/sudoers.d/99-anything` was never denied by it.

It survived the original sandbox tests because the test policy was written the same way, and its
globs expanded onto the test files that existed. Now quoted, with a regression test that writes
to a *new* file under a denied prefix and requires a refusal.

### Root jobs cannot see your ssh config — a trap that hits every scheduled push

`sftp:desktop:` resolves through the *calling user's* `~/.ssh/config`. Root has no `desktop`
host, no key, and an empty `known_hosts`, so any root-run restic job fails with
`Host key verification failed` — at 04:10 on a Sunday, into a log nobody reads. Both
`backup-restic.sh --system` and `timeshift-ship` hit it within a minute of each other.

The fix is not to give root a key or to disable host checking. Both jobs now name the identity
and point at Chris's already-verified `known_hosts`:

```
-o sftp.command="ssh -i /home/USER/.ssh/id_ed25519 \
   -o UserKnownHostsFile=/home/USER/.ssh/known_hosts desktopuser@192.0.2.65 -s sftp"
```

### The wrapper trap

If the NOPASSWD wrapper is writable by `chris`, the agent has unaudited root — it just edits
the wrapper. So:

- `/usr/local/sbin/mrog-apply`, owner `root:root`, mode `0755`, **on the T3 never-touch list**
- sudoers grants NOPASSWD **only** for that exact path, no wildcards, no `ALL`
- the allowlists it reads live in `/etc/mrog/` — also root-owned, also T3
- installing or changing either is a Chris action, done deliberately, once

If real containment is ever wanted, the honest options are: (a) a separate non-sudo `agent`
user with polkit rules for specific actions, or (b) agents run inside a VM that has only
declared host paths. Both are heavier. Note them, don't build them yet.

---

## 3. The verb surface

Agents should never improvise `sudo` pipelines. They call one command with predictable verbs,
which is what makes an allowlist, a hook denylist, and a log grep all possible.

Working name: `mrog` (user-level driver) + `mrog-apply` (the root half).

```
mrog snapshot [label]        # take a restore point, print its id
mrog rollback <id>           # restore /etc (or full) from a restore point
mrog diff <file>             # show pending change vs on-disk
mrog apply <patchfile>       # T2: snapshot -> validate -> apply -> journal
mrog svc <restart|status> <unit>
mrog pkg <add|remove> <name> # T1, pinned allowlist
mrog net apply <file>        # T2 + auto-revert timer
mrog profile <save|load|list> <name>   # user-level, no root
mrog audit [--since]         # read the change journal
mrog doctor                  # drift: packages, enabled units, /etc dirty state
```

Design rules:

- every mutating verb supports `--dry-run` and prints a real diff
- `apply` refuses unless the dry-run output hash matches what was reviewed (no silent drift
  between "what I showed you" and "what I did")
- **one line per invocation** in the journal — Chris pastes single lines, agents call single verbs
- exit codes are meaningful: 0 applied, 10 no-op, 20 validation failed, 30 refused by policy

### Change journal

`/var/log/mrog/changes.jsonl`, append-only, one object per apply:

```json
{"ts":"2026-09-02T20:12:03-05:00","sid":"LINUX-MN5","verb":"apply","target":"/etc/sysctl.d/99-vm.conf",
 "snapshot":"ts-20260902-2012","validator":"sysctl -p --dry-run: ok","diff_sha256":"…","result":"applied"}
```

Rotate it, mirror it to Hub nightly, and let `mrog audit` read it. This is the artifact
that makes "what did the agents change last week" a one-command question.

---

## 4. Reversibility — Phase 0, and nothing agentic happens before it

1. **etckeeper + git in `/etc`.** Highest value per minute spent. Every root config change
   becomes a commit with a message and an author. `mrog apply` commits with the SID in the
   message. Push the `/etc` repo to Hub — it is small, and it is the machine's identity.
2. **Timeshift, fixed — and kept local, on purpose.** Chris asked for the shared drive as the
   Timeshift target. **Timeshift cannot do that.** It takes rsync + hardlink snapshots on a
   *mounted block device* it can restore from before the network exists; CIFS/SSHFS break
   hardlinks and ownership, and a restore that depends on the Desktop being up is not a restore.
   (`/data/share/timeshift` works **on the Desktop** because there the share is a local ext4 disk.)
   So: Timeshift stays on the root disk as the **undo layer, taken by hand**, and a weekly job
   ships the newest one to the share — `timeshift-ship`, Sundays 04:10. It never creates a
   snapshot, warns loudly (and on screen) if the newest is more than 21 days old rather than
   quietly shipping stale data, and proves the shipped snapshot is in the repo instead of
   trusting an exit code. The share gets the real off-machine backup either way, below. Same-disk snapshots are typo insurance,
   not disk-failure insurance; both layers are needed and they are not the same tool.
3. **restic to the shared drive — the off-machine layer.**
   ⚠️ **Before copying the convention, know that it is broken.** The Desktop's own
   `omarchy-backup.service` failed *every scheduled run from Aug 31 to Sep 3* — systemd
   gives it no `HOME`, restic cannot open a cache, exit 1. The timer fires, the repo directory
   exists, and old snapshots are present — while **the newest was four days stale**. (Two
   snapshots from Aug 30, then every scheduled run failed; fixed 2026-09-03 with a drop-in
   setting `HOME`, and the next run landed 227 GiB.) The laptop's
   `~/mrog/backup-restic.sh` therefore asserts a fresh snapshot exists after every run and has
   a `--check` staleness mode. Fix for the Desktop staged at `desktop:/tmp/fix-omarchy-backup.sh`. The share already holds
   `/data/share/backups/omarchy-restic` + a `.KEY`, so this machine joins the same convention as
   `/data/share/backups/laptop-restic`, pushed over SSH as `desktopuser`.
   Two things must be settled first:
   - `/data/share/backups` is `root:fleetshare` and `desktopuser` is **not** in `fleetshare`,
     so the repo directory has to be created on the Desktop by root, once, and chowned.
   - The Omarchy convention stores `omarchy-restic.KEY` **beside the repo**. Anyone who can read
     the share gets both the ciphertext and the key. This laptop's key should live in `~/.vault`
     and on Hub, *not* on the share — recommendation, Chris's call.
4. **Machine manifest.** `apt-mark showmanual`, enabled unit list, dconf dumps, `~/bin`,
   `/etc/sudoers.d` inventory, kernel cmdline, driver state → one timestamped tarball, pushed
   off-machine. This is what makes a rebuild reproducible rather than archaeological.
   `fleet-capture.sh` is Debian-shaped and this box *is* Debian-shaped, so it should work here
   — verify it actually populates the package lists rather than passing green while empty.
5. **A restore drill.** Not a file count. Restore into a VM, boot it, log in. The fleet has
   already been burned by a 29,154-file "healthy" backup missing 26.84 GB, by an all-zero
   27.6 GB archive, and by `e3b0c442…` (the SHA-256 of nothing) passing a verify step.
6. **Repos with no remote.** Before agentic edits start, find every git repo on this box whose
   only copy is here and give it a remote on Hub.

**Done-when for Phase 0: MET 2026-09-03.** `bash ~/mrog/restore-drill.sh sandbox` → **DRILL
PASSED**. It proves, in one run: a fresh snapshot lands; the key copy *fetched from Hub*
(not the local one) opens the repo; `~/bin`, `~/mrog`, `docs`, the launcher entries and
the Cinnamon panel config restore byte-identical; and the restored tree lands on a clean machine
that has never seen it, with hash manifests computed independently on both ends agreeing
(`f2ff70507095335d`).

**The drill's own first version was wrong**, and the way it was wrong is worth keeping: it
compared a snapshot taken hours earlier against a live home directory and called ordinary drift
a failure — the only "fault" it found was this handbook, edited after the snapshot. A restore
check has to either shrink the window (snapshot immediately before restoring) or ask whether a
differing file was written *after* the snapshot. It now does both. A verification that cries
wolf gets ignored, which is how a real fault slips through.

---

## 5. Guardrails

### Never-touch (T3) list — the file the wrapper reads

```
/boot/**, /etc/default/grub, /etc/fstab (device lines), /etc/crypttab
/etc/sudoers, /etc/sudoers.d/**, /usr/local/sbin/mrog-apply, /etc/mrog/**
/etc/passwd, /etc/shadow, /etc/group
~/.ssh/**, ~/.vault/**, ~/LINUX_SECRETS.tgz.gpg
Any WireGuard or Tailscale key material
```

### Claude Code side

- `settings.json` permissions: allow the `mrog` verbs; **deny** raw `sudo`, `rm -rf /`, `dd`,
  `mkfs*`, `cryptsetup`, `passwd`, `chown -R /`, and any read of `~/.ssh` or `~/.vault`.
- A `PreToolUse` hook on Bash that regex-blocks the denylist and appends every command to a
  per-session audit log. **This matters more here than on other boxes: sessions on this
  machine run in AUTO mode, so a permission prompt is not the brake. The hook and the wrapper
  are the brake.**
  → **Written and tested 2026-09-03:** `~/mrog/hooks/guard-bash.sh`, logging to
  `~/.claude/bash-audit.log`. Blocks `mkfs`/`cryptsetup`/partition tools, `dd` onto a raw disk,
  recursive deletes of system trees, reading key material into a transcript, sending key
  material off-machine, `sudoers`, and **raw `sudo`** — root has to go through `mrog-apply`
  under a lease or through Chris. It fails *open* on malformed input, so a broken hook can
  never wedge a session. Installed by Chris 2026-09-03 with `bash ~/mrog/install-claude-guard.sh`.

  **v2, within twenty minutes of going live** (`~/mrog/hooks/guard-bash.v2.sh`): v1 matched the
  raw command, so any command that merely *mentioned* a blocked word — an `echo`, a `grep`
  pattern, a log search — was refused. v2 matches a quote-stripped copy, on the principle that
  text inside quotes is data; the exception is a shell `-c` wrapper, where quoted text *is* the
  command, so the raw string is scanned as well. v2 also protects its own file and
  `~/.claude/settings.json` from Bash edits, which v1 did not.
  Regression suite: `bash ~/mrog/hooks/test-guard.sh <guard>` against
  `~/mrog/hooks/guard-cases.txt` — **v1 25/31, v2 31/31**.

  **Known limit, stated plainly:** the hook only sees *Bash* tool calls. File edits made through
  the Write/Edit tools do not pass through it — which is how v2 itself got written while v1 was
  blocking Bash edits of the guard. It is a brake on shell execution, not a sandbox.
- A `PostToolUse` hook that flags any write under `/etc` that did not go through `mrog apply`.

### Blast-radius rules worth writing into the wrapper

- **Never address a disk as `nvme0`/`nvme1`.** Kernel names have already swapped across a
  reboot on this machine (root moved `nvme0n1p2` → `nvme1n1p2`). UUID or serial only.
- **Network and graphics changes get an auto-revert timer** — apply, arm a 90 s timer, require
  a heartbeat to disarm. A fleet-access-point laptop that loses WireGuard mid-session while an
  agent is driving it is the worst case, and it is cheap to prevent.
- **Two windows, one file** poisons `.bak` snapshots. Chris runs up to 4 concurrent sessions;
  the wrapper should take a lock per target path and refuse rather than queue.
- **Anchor patches on 2+ lines.** Substring anchors have already caused inert-but-green fixes.

---

## 6. Validate before it lands

| Change type | Validator that must pass first |
|---|---|
| shell script | `bash -n` + `shellcheck` (install it) |
| systemd unit | `systemd-analyze verify`, then reload + restart with a rollback timer |
| sudoers | `visudo -c -f <file>` — and this is T3 anyway |
| sysctl | `sysctl -p --dry-run` equivalent, then read back the live value |
| fstab | `findmnt --verify`; a rescue entry stays in place; T3 |
| nginx / sshd | `nginx -t`, `sshd -t` (sshd: never restart the running session's daemon without a second session open) |
| desktop / dconf | dump before, dump after, diff — see §8 |
| kernel cmdline / grub | T3, and only with a known-good snapshot and a live USB in the drawer |

### Sandbox twin — built 2026-09-03

`mint-sandbox` is **defined and shut off**: 4 vCPU, memory 8 GiB / currentMemory 4 GiB with a
virtio balloon, UEFI (OVMF), virtio disk + NIC on the default NAT network, 60 G qcow2 thin
(196 KiB allocated), Mint 22.3 Cinnamon ISO attached and set to boot first. The ISO was verified
twice — sha256 against Mint's GPG-signed `sha256sum.txt` (key `27DE B156 44C6 B3CF 3BD7 D291
300F 846B A25B AE09`), then again after upload into the libvirt pool. Start it and run the
installer when convenient; eject the ISO afterwards so it boots the installed system.
XML kept at `~/mrog/mint-sandbox.xml`.

### Sizing rationale

libvirt is already here and `win10-riprint` proves the path works. The rule: *if a change could
stop the laptop from reaching a login screen, it lands in the VM first.*

| | Windows 10 (today) | `mint-sandbox` (proposed) |
|---|---|---|
| Disk | qcow2 120 G virtual, **22.4 G actually used** | qcow2 **60 G virtual**, ~12–15 G after install |
| RAM | 8 GiB fixed, `<memballoon model='none'/>` | **4 GiB baseline, ballooning to 8** (virtio-balloon) |
| vCPU | 4 of 16 | 4 of 16, `current=2` for hot-add |
| Store | `/var/lib/libvirt/images` (root disk) | same — ruled: local drive, not `nvme1n1p2` |

**Answers to the three questions.** *How much space:* nothing up front — qcow2 is already
thin-provisioned, so a 60 G virtual disk costs what the guest writes (~12–15 G for Mint 22.3 plus
updates; give it 60 so a snapshot chain and a second kernel fit). Against 743 G free, both VMs
together are noise. *Adjust current allocation:* only if both run at once — 8 + 8 of 23 GiB leaves
the host squeezed with Claude Desktop and Firefox up. Drop Windows to 6 GiB (RIPrint/LightBurn
never needed 8) and it is comfortable; that is an XML edit while the VM is shut off, no guest
changes. *Dynamic:* disk yes, already. RAM yes **for the Linux guest** — virtio-balloon is in the
kernel, so `virsh setmem mint-sandbox 6G --live` works. For the **Windows** guest it would need
the virtio-balloon driver installed inside a deliberately offline, byte-verified appliance —
not worth touching it; give Windows a smaller fixed number instead.

---

## 7. Lean machine track (no root risk, do it early)

- `systemd-analyze blame` / `critical-chain` → list what actually costs boot time
- `systemctl list-unit-files --state=enabled` (92 today) → sign off on a baseline; anything
  new that appears later is drift, not a mystery
- `apt-mark showmanual` → the intentional package set; everything else is removable in principle
- idle RAM and idle CPU budget, measured once, recorded, then re-checked weekly
- a `mrog doctor` weekly report that diffs today against the signed-off baseline and mails or
  posts the delta — the same instinct as the fleet's freeze table, applied to this box
- watch out: a failure streak with no reset is a fossil. Any monitor added here needs a
  last-run timestamp, or a stale alert will be read as a live one.

---

## 8. Profiles and workspace switching (the Omarchy-envy track)

This is the part that is pure upside: **entirely user-level, zero root, fully revertable**, so
it can start before the agentic-root work is finished.

### Built 2026-09-03 — `~/bin/profile`

```
profile save <name> [--note "why"]   snapshot the desktop as it is right now
profile load <name> [--no-restart]   switch to it (auto-saves the current one first)
profile diff <name>                  what would change if you loaded it
profile clone <from> <to>            derive a new profile from an existing one
profile list | current
```

It carries four dconf subtrees (`/org/cinnamon/`, `/org/nemo/`,
`/org/gnome/desktop/interface/`, `/org/gnome/desktop/wm/preferences/`), the applet configs in
`~/.config/cinnamon/spices/` (that is where the launcher bar lives), `~/.config/autostart/`,
the power profile, and an optional `hook.sh` run after the switch. Cinnamon is restarted at the
end because applet and icon caches refresh no other way.

**Every load auto-saves the current desktop first** as `_before-<timestamp>` (last five kept),
so any switch is undoable with one command — the same snapshot-before-change doctrine as
`mrog-apply`, applied to the desktop.

**Proved by round trip:** panel autohide and the launcher list were changed on purpose, then
`profile load FLEET` put both back. That test also exposed a real gap — the first `diff` only
compared dconf and reported "identical" while the bar was visibly wrong, because the launcher
list lives in `spices/`. `diff` now covers dconf, applet configs, autostart and the power
profile.

Profiles that exist:

| Profile | What it switches |
|---|---|
| **FLEET** | the desk setup as it stands — fleet launcher bar, balanced power, nothing sleeps |
| **TRAVEL** | power-saver · screen off at 5 min on battery · suspend at 15 · lid closes to suspend · lock on wake (on FLEET every one of those is off) |
| **SHOP** | performance · notifications off · screen never sleeps on AC · hook starts `win10-riprint` and opens the viewer |
| **VOID** | Isolate Vocals back on the launcher bar · hook mounts the fleet share quietly |
| **CLEAN** | generic launcher bar (Firefox/Files/Terminal) · notifications off · different wallpaper so the profile is obvious at a glance |

CLEAN is for screen sharing, and its hook says out loud what it does *not* hide: window titles,
terminal scrollback, browser tabs.

### Two traps this design has, both hit on the first day

1. **A global setting added after the profiles were saved gets wiped by the next load.** The
   `Super+Space` binding was created after all five profiles existed; because `dconf load -f`
   resets the whole subtree, the first `profile load` would have silently removed it. Anything
   meant to be global has to be written into *every* profile — there is no "shared base layer".
2. **`dconf dump` sorts sections, so an appended section makes an identical profile look
   different.** `profile diff` reported drift when the data matched exactly. Both stored dumps
   and the live dump now pass through `~/mrog/dconf-normalize.py` (sections and keys sorted), so
   the comparison is semantic rather than textual.

### The leader key — `~/bin/leader`, bound to `Super+Space`

One menu over the same verbs the agents use, so a human action and an agent action are the same
action with the same log line: switch profile, undo the last switch, run or check the backup,
grant/inspect/end a root lease, drift report, read the agent audit log, start either VM, open the
share, pull the JOURNAL, open the Hermes dashboard. Entries that prompt for anything (a password,
a fleet session) open in a real terminal. It uses `rofi` when installed and falls back to
`zenity`, which is already here — so it works today and gets nicer later.
`leader --list` prints the menu with no window, which is how it is tested.

### Keybinding table

`Super+Space` leader · `Super+1..5` load FLEET/TRAVEL/SHOP/VOID/CLEAN · `Super+A` agent audit.
Written into every profile by `~/mrog/add-keybinds.py`, because a binding that lives only in the
live desktop is wiped by the next `profile load`.

### Fleet Status desklet — the Quickshell-plugin equivalent

`~/.local/share/cinnamon/desklets/fleetstatus@laptop/` renders whatever
`~/bin/fleet-status --multi` prints — profile, lease, snapshot age, backup freshness, VMs up —
refreshed every 20 s, and clicking it opens the leader menu. Widget, shell and agents all read
the same state from the same script, which is the whole point.

### The desklet froze the machine — twice-wrong, worth keeping

Within half an hour of installing the Fleet Status desklet the laptop became unusable.
`fleet-status` was calling `backup-restic.sh --check`, which opens the restic repo **over sftp**:
51.65 seconds. The desklet called it with `GLib.spawn_command_line_sync`, which runs on
Cinnamon's **main loop**, on a 20 second timer — so the compositor was blocked more than
full-time and refreshes queued behind each other.

The tell that makes this hard to spot: **load average stays normal** (0.85) while the desktop is
dead, because a blocked main loop is not a busy CPU.

Both halves are now fixed and both were necessary: a widget's status script must be local and
fast (backup freshness is read from `~/.config/mrog/backup-status`, written by the backup job;
everything else has `timeout 2`; 51.65 s → **0.04 s**), and the desklet uses `Gio.Subprocess`
with an async callback, scheduling its next refresh *before* spawning.

Emergency off-switch, which works even when the desktop is crawling:
`gsettings set org.cinnamon enabled-desklets "[]"`

### The agent layer

`codex`, `gemini`, `opencode` and `crush` are installed (npm under nvm, user-owned, no root), and
`~/.config/agents/AGENTS.md` is now the single instruction file, symlinked to `~/.claude/CLAUDE.md`,
`~/.codex/AGENTS.md` and `~/AGENTS.md` — the Omarchy layout. The stale
`~/.codex/AGENTS.md.windows-original` is superseded.

**Profiles are code now.** `~/mrog/build-profiles.py` regenerates TRAVEL, SHOP, VOID and CLEAN
from FLEET, preserving each one's hand-written `hook.sh`. When a global setting changes, re-save
FLEET and re-run it, rather than hand-patching five directories — the hand-patching approach
broke twice in one hour, once on a regex that tripped over a `[` inside a value.

A profile is a named directory of dumps plus a manifest:

```
~/.config/mrog/profiles/<name>/
  cinnamon.dconf        # dconf dump /org/cinnamon/
  keybindings.dconf     # dconf dump /org/cinnamon/desktop/keybindings/
  nemo.dconf, interface.dconf
  autostart/            # .desktop files to link into ~/.config/autostart
  launchers.json        # the left-bar launcher list for this profile
  manifest.sh           # power profile, dGPU mode, wg up/down, DND, apps to open
```

`mrog profile save <name>` dumps the live state; `mrog profile load <name>` restores it and
runs the manifest. Because it is all dconf, the worst failure is a wrong wallpaper.

### Profiles worth having

| Profile | What it does |
|---|---|
| **FLEET** | agent windows, JOURNAL + dashboards, WireGuard up, notifications on, performance profile |
| **SHOP** | Windows VM + laser tooling, notifications off, screen never blanks, dGPU on |
| **VOID** | audio tooling, Desktop share mounted, monitoring dashboards |
| **TRAVEL** | battery profile, dGPU off, charge limit 60, heavy autostarts disabled, tunnels down |
| **CLEAN** | a bare desktop for screenshots and screen sharing — no fleet names visible |

### Leader key

Bind `Super+Space` to a fuzzy launcher over the **same verb surface** the agents use, so a
human action and an agent action are the same action with the same log line. `rofi` is the
natural choice (not installed yet); `zenity` is present and works for a v0 menu.

### Workspaces

Cinnamon workspaces get names per profile (Fleet / Shop / Void / Scratch) and each profile's
manifest declares which apps open where. Cinnamon's `wm-preferences` and `Expo` cover the rest.

### Alt session — flagged, not recommended yet

A second session (Hyprland-style) alongside Cinnamon is possible and would feel most like
Omarchy. Risk on this box: hybrid Intel/NVIDIA graphics on the Zephyrus plus Wayland is where
laptops stop reaching a login screen. If it is ever attempted: sandbox VM first, Cinnamon stays
installed and default, and it happens with a snapshot and a live USB present.

---

## 9. Phased rollout

**Phase 0 — Foundation (blocking).** Written and waiting for one paste:
`sudo bash ~/mrog/phase0-foundation.sh` — sudo audit → `~/mrog/audit/`, installs etckeeper +
git + shellcheck + restic, puts `/etc` under git with the first commit, turns the Timeshift
schedule on. Still to do after it: the restic repo on the share (needs one root command on the
Desktop), the manifest tarball, a restore drill, and remotes for remote-less repos.
*Done-when: a broken `/etc` file is reverted in one command and a restored image boots.*

**Phase 1 — Verb surface.** Written, inert, and tested in a sandbox: `~/mrog/{mrog,mrog-apply,
mrog-lease,policy.conf}`, installed by `sudo bash ~/mrog/install-mrog.sh` **after** the sudo audit
has been read. Then Claude Code permissions and hooks.
*Done-when: `mrog snapshot` refuses with no lease; Chris grants 10 minutes; an agent changes a
sysctl end to end — diff, token, validate, apply, `/etc` commit, journal — and `mrog revert`
undoes it; the lease lapses on its own and the next attempt refuses.*

**Phase 2 — Profiles.** Save the current desktop as `FLEET`, build `TRAVEL` and `SHOP`, add the
leader key. No root anywhere in this phase.
*Done-when: `mrog profile load TRAVEL` visibly changes power, panel, autostart and tunnels, and
loading `FLEET` puts it all back.*

**Phase 3 — Lean pass.** Baseline sign-off, service pruning, `mrog doctor` weekly drift report.

**Phase 4 — Deeper customization.** Theming, kernel parameters, alt session — each rehearsed in
the sandbox VM, each with a snapshot.

Phases 0 and 2 have disjoint file ownership and can run in two parallel windows. Phase 1 owns
`/etc` and `/usr/local/sbin` and should be alone.

---

## 10. Decisions only Chris can make

1. ~~**NOPASSWD scope.**~~ **Decided 2026-09-02: approval + lease timeout.** NOPASSWD covers one
   inert binary; arming it always costs a password. See §2.
2. ~~**The 477 G NTFS volume.**~~ **Decided: out of scope**, to be wiped, use undecided.
   Sandbox and snapshots both live on the root disk.
3. **Unattended `apt install`?** Partly answered: `pkg add` is limited to `MROG_PKGS` in
   `/etc/mrog/policy.conf` and needs a live lease. Open question is how long that list gets.
4. ~~**Sandbox VM: yes/no.**~~ **Decided: yes**, alongside the Windows VM. Sizing in §6.
5. **Encryption.** The root FS is unencrypted and cannot be encrypted in place. Options: accept
   and keep nothing irreplaceable local; a LUKS container file for working secrets; or a future
   reinstall with full-disk encryption. Worth deciding now because it changes what Phase 0's
   off-machine copy has to contain.

---

### Still open for Chris

- The restic repo directory on the Desktop (`/data/share/backups/laptop-restic`) needs one
  root command there, because `desktopuser` is not in `fleetshare`.
- Where the restic key lives — `~/.vault` + Hub (recommended) or beside the repo like
  `omarchy-restic.KEY` (the existing convention, which stores key and ciphertext together).
- Whether Windows drops from 8 GiB to 6 GiB so both VMs can run at once.

---

## 11. Appendix — desktop changes made 2026-09-02, and how to drive Cinnamon from an agent

### What changed

- Left auto-hide panel (`panel2`) now carries a **Panel launchers** applet (instance `15`),
  registered in `org.cinnamon enabled-applets` as `panel2:left:0:panel-launchers@cinnamon.org:15`.
- Bar contents, top to bottom: VS Code · Windows 10 · Fleet Drive · Hermes · Dreamzs Legal Mode ·
  Save Latest JOURNAL · ROG Control.
- The three Hermes launchers collapsed into one `hermes.desktop` with desktop **actions**:
  left click opens the dashboard, right click branches to *Manager Session*, *The Void Session*,
  *Shell on the Hermes account*.
- `Isolate Vocals (Void)` stays installed and menu-searchable, but is off the bar.
- Three launchers had colliding or meaningless icons (two identical grey monitors); now
  `virt-manager` (VM), `cs-power` (ROG), `application-certificate` (Legal Mode).
- `~/Desktop` is empty. Every original file is at
  `~/.local/share/desktop-icons-backup-20260902/` (superseded Hermes entries under `superseded/`).

### Reusable operational knowledge (this cost real time to learn)

- Launcher list lives in `~/.config/cinnamon/spices/panel-launchers@cinnamon.org/15.json`
  under `launcherList.value`, as `.desktop` basenames resolved through the app system.
- **Editing that JSON externally does not take effect** — Cinnamon does not reload it. Follow
  with `dbus-send --session --dest=org.Cinnamon /org/Cinnamon org.Cinnamon.ReloadXlet
  string:'panel-launchers@cinnamon.org' string:'APPLET'`.
- **Changing a `.desktop` `Icon=` does not take effect on a reload either** — the icon comes
  from the app-system cache. `update-desktop-database`, `touch`, and ReloadXlet all fail to
  refresh it. A full Cinnamon restart is required:
  `dbus-send --session --dest=org.Cinnamon /org/Cinnamon org.Cinnamon.Eval string:'imports.ui.main.restartCinnamon(true);'`
- `global.reexec_self()` through `Eval` returns success **without restarting** — it looks like
  it worked and does nothing. Use `imports.ui.main.restartCinnamon(true)`.
- `Eval` does execute (verified with `global.log`), but `imports.ui.appletManager.appletObj`
  is empty in Cinnamon 6.6 — do not use it to introspect live applets. Screenshot instead.
- Desktop **actions inherit `Terminal=true`** from the main entry group (verified on GLib
  2.80): an action's `Exec` opens in the default terminal, no wrapper needed.
- Panel autohide is `org.cinnamon panels-autohide`, per panel: `['1:false','2:true','3:false']`.
  Flip panel 2 to `false` to screenshot the bar, then flip it back.
