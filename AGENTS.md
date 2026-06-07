# AGENTS.md

Guidance for agents working in this repository.

## Project Scope

This repo contains helper scripts for maintaining Sovol SV08 printers running
mainline Klipper. The scripts are intended to run on the printer host over SSH
and automate firmware configuration, device detection, build, and flashing for
the SV08 mainboard, toolhead, and supported Eddy sensors.

Hardware flashing can damage equipment if the wrong target or serial device is
used. Treat changes here as safety-sensitive.

## Agent Role

Agents should help maintain the project end to end, not only generate files or
patches. When asked for help, work through the underlying issue, inspect the
relevant scripts and documentation, explain tradeoffs, and provide clear
operator guidance. If a direct code change is appropriate, make it; if the
request is about usage, troubleshooting, or safety, answer with practical steps
and call out assumptions.

When troubleshooting:

- Ask for or inspect the exact command, host environment, Klipper path, and
  relevant `printer.cfg` MCU sections before recommending flashing.
- Distinguish local development checks from commands that must run on the SV08
  host.
- Prefer guidance that reduces hardware risk: confirm targets, preserve config,
  and make rollback steps clear.
- Explain what could not be verified without access to the printer host.

## Repository Layout

- `README.md`: user-facing setup, usage, and project context.
- `LICENSE`: MIT license.
- `scripts/`: shell scripts and helper commands.

## Development Guidelines

- Prefer POSIX-compatible shell where practical, but preserve Bash-specific
  behavior if an existing script uses Bash intentionally.
- Use strict shell settings in new scripts when feasible:
  `set -euo pipefail`.
- Quote variable expansions unless word splitting is explicitly required.
- Keep hardware-specific constants and detected device paths easy to audit.
- Avoid hard-coding `/dev/serial/by-id/*` values for a single machine.
- Before adding dependencies, verify they are likely available on common SV08
  host images or document installation steps in `README.md`.
- Preserve interactive `make menuconfig` flows where users need to confirm MCU
  settings.

## Safety Requirements

- Never skip checks that stop Klipper or release serial devices before flashing.
- Do not broaden device matching in a way that could flash the wrong MCU.
- When modifying detection logic, include clear failure behavior if no exact
  target is found or if multiple ambiguous targets are found.
- Do not add commands that reboot, power-cycle, erase, or flash hardware without
  making the target and intent explicit to the user.
- Keep the disclaimer and cold-printer/no-active-print warnings in user-facing
  documentation.

## Verification

For shell changes, run these checks when available:

```bash
shellcheck <script>.sh
bash -n <script>.sh
```

If a change affects hardware flashing, also verify the dry-run or detection path
on the target host where possible before recommending real flashing. Document any
verification that could not be performed locally.

## Documentation

- Update `README.md` when script names, flags, supported boards, supported Eddy
  variants, required packages, or operator steps change.
- Keep README commands aligned with the actual script paths and supported flags.
- Keep examples copy-pasteable for the default SV08 host workflow.
- Mention hardware risk clearly when introducing new flashing behavior.

## Git Hygiene

- Leave unrelated untracked or modified files untouched.
- Keep commits scoped to the script or documentation behavior being changed.
- Do not rewrite history unless the user explicitly asks for it.
