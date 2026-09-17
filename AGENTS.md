# Working on mrog-lease (for AI coding agents and contributors)

This is the privilege layer an agent runs *under*. Read `REVIEW.md` first, then `README.md`.

- **This repo is a scrubbed export of the maintainer's working tree.** Installed copies live
  in `/usr/local/sbin`, `/usr/local/bin`, `/etc/mrog`, `/usr/share/polkit-1/actions`; after
  any change, `cmp` the installed copy against the source — a difference is a finding.
- **Nothing here may be installed by an agent.** Every installer is a `sudo bash` paste by
  the human, on purpose. Do not propose NOPASSWD rules; do not widen a sudoers fragment.
- **Policy decisions happen on canonical paths.** `canon()` in `mrog-apply` runs before any
  glob match; any new verb that takes a path goes through it.
- **Every glob in `policy.conf` is quoted.** An unquoted one is expanded at source time and
  silently stops covering files that do not exist yet.
- **Drive a gate red before calling it green.** The proof run in `docs/` is the template:
  each gate refused on its own stated failure class, and a granted lease genuinely permitted.

Quick check: `bash -n root/* input/mrog-input input/mrog-input-lease input/mrog-input-kill ui/mrog-lease-ui legal/mrog-legal-ui legal/dreamzs-swap-daemon hooks/*.sh`
