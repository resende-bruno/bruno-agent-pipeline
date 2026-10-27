---
name: pipeline-builder
description: Guided, phase-by-phase setup of a remote agent dispatch pipeline (gateway agent + SSH forced-command dispatch + Dockerized coding agent). Use when the user asks to build, set up, or adapt this pipeline for their environment. The skill assists and verifies; the user reads the docs and makes every infrastructure decision themselves.
---

# Pipeline builder

You are helping a developer build their own instance of the remote agent dispatch pipeline
documented in this repository (`docs/01` through `docs/07`). Read `docs/01-architecture.md`
yourself before starting, and read each phase's doc before running that phase.

## Operating rules (these override your defaults)

1. **The user decides, you implement.** At every decision gate below, present the decisions from
   the doc's "⚠ Decisions you must make" section as numbered questions, tell the user which doc
   section explains the trade-offs, and **wait for their answers**. Never pick a provider,
   network exposure, permission setting, or security posture on their behalf, not even as a
   "sensible default" they can override later.
2. **Default to the good practice; deviations are theirs to own.** Recommend and build the
   recommended path (private overlay network, forced command, deny-lists, secrets in
   permission-restricted files). If the user chooses otherwise, implement their choice without
   re-arguing it more than once, but state in one line what property they're giving up.
3. **Secrets never touch the conversation.** Never ask the user to paste a key, token or password
   into chat; never echo one in your output; never write one into a repo file. Have them place
   secrets in files directly (give them the path and the permission-tightening command), and
   reference those paths in configs.
4. **Do not proceed past a failing acceptance test.** Each phase ends with verification. If it
   fails, diagnose and fix before the next phase. A half-verified pipeline is worse than none,
   because its failures are silent.
5. **Adapt, don't transplant.** The templates are illustrations. Port idioms to the user's OS,
   shell, gateway platform and agent CLI, but keep every invariant marked in the docs (quote-safe
   task transport, detached START, bounded finalize operations, explicit scheduler timeouts,
   deny-lists).

## Phase 0 - inventory and decisions

Ask the user to read `docs/01-architecture.md` first. Then collect:

1. Dev machine OS and shell; container runtime present?
2. Always-on host for the gateway (existing VPS? needs one?)
3. Gateway platform (reference: OpenClaw) and messaging channel
4. Coding agent CLI (reference: Claude Code). Confirm it supports headless mode, permission
   deny-lists, and session continuity; if any is missing, stop and discuss what that changes
5. Network link between the two machines (recommend a private overlay network; see docs/03)
6. Project root folders the dispatch script may resolve projects under

Do not continue until all six are answered by the user.

## Phase 1 - dispatch channel (docs/03)

- Walk the user through generating the dedicated keypair (they run `ssh-keygen` themselves) and
  installing the overlay network on both machines.
- Write the `authorized_keys` entry with the forced command and all `no-*` options.
- **Acceptance:** from the gateway host, `ssh -i <key> -o BatchMode=yes <dev> "anything"` must
  run the dispatch script's error path (once Phase 2 exists, re-test), and an attempt to open an
  interactive shell with that key must fail.

## Phase 2 - container runner (docs/04)

- Build the container image from `templates/Dockerfile` (adapted to their agent CLI).
- Port `templates/dispatch.ps1` to their OS/shell if needed, keeping the documented contract.
- Create the settings/deny-list file; have the user place the agent token in a
  permission-restricted file themselves.
- **Acceptance:** run all five acceptance tests listed at the bottom of `docs/04`, especially
  the hostile-task-text test (quotes, `$variables`, backticks, a literal `$(reboot)`) verified
  byte-for-byte inside the container.

## Phase 3 - gateway agent (docs/02)

- Install/configure the gateway platform and messaging channel (account creation and OAuth are
  the user's hands-on steps; never handle their credentials).
- Adapt `templates/AGENTS.md` into the gateway's instruction file, with the user's placeholders.
- Configure the exec allowlist for exactly the dispatch SSH invocation; confirm how their
  platform matches patterns (argv vs. raw string) by testing, not assuming.
- **Acceptance:** a real dispatch from the messaging channel round-trips: confirmation shown,
  START fires without a manual approval prompt, ticket returned. And a deliberately off-pattern
  command from the gateway gets held for human approval instead of executing.

## Phase 4 - reliability layer (docs/05)

- Register the standing watchdog automation (sweep every ~3 min) and add the finalize-watcher
  template (with explicit job timeout) to the gateway's manual.
- **Acceptance:** (a) a dispatch whose finalize watcher is deliberately not registered still
  delivers full results via the watchdog within one sweep interval; (b) a task that runs longer
  than the scheduler's *default* job timeout still delivers its finalize (proves the explicit
  timeout is set and honored).

## Phase 5 - memory (docs/06)

- Initialize the memory repo from `templates/memory-repo/`, adapt `_shared/CLAUDE.md` with the
  user, set up the private remote with a dedicated deploy key (user generates it).
- **Acceptance:** a dispatch writes a findings summary to the project's NOTES.md and the finalize
  output shows the memory commit; a second dispatch on the same branch demonstrates continuity.

## Phase 6 - workflow layer (docs/07)

- Work through `docs/07`'s decision list: which lifecycle stages, which named reviews, which
  finish-up checks, where the human-only line sits. These are pure user decisions; your job is
  to record them into the gateway manual and memory conventions, not to choose them.
- **Acceptance:** a new-idea message triggers echo-back before any prompt; a "start phase N"
  message does not; an implementation dispatch's output ends with the finish-up check lines.

## Done

Summarize what was built, where every config lives, and the two or three operational facts the
user must remember (session refresh after manual edits, scheduler timeout rule, what to check if
results stop arriving). Encourage them to run the first real feature through the full lifecycle
while everything is fresh.
