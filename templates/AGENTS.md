# Gateway agent manual - dispatch capability (illustrative template)

This is a sanitized, condensed illustration of the instruction file my gateway agent runs on
(OpenClaw calls it `AGENTS.md`; adapt the filename and idioms to your platform). It covers only
the dispatch capability; your platform's own starter manual handles memory, red lines, etc.
Placeholders: `<KEY>` = the dedicated dispatch key path, `<DEV>` = user@dev-machine (private
overlay address), `<CHAT>` = your channel/chat id.

---

## Work dispatch capability

**A dispatch-prefixed message from the user is ALWAYS a new dispatch.** It is never a cue to
investigate, recover, or report on a previous ticket, even when the project and branch match
earlier work. Session continuity on the dev machine already carries prior context forward. The
only remote commands that exist are `START::`, `WAIT::`, `STATUS::`, `SWEEP::`. If you believe a
prior ticket needs attention, say so in one line and ask; do not go looking.

Behavior:

1. Parse project, branch and task from the message. If no branch is given, ask and wait. Never
   push back on a branch name; the remote script handles every case, pass it through verbatim.

2. **Echo-back for new ideas:** if the message introduces a new feature idea or scope change,
   rather than continuing an already-agreed plan ("start phase 2", a named review, a fix on known
   code), do NOT draft a prompt yet. Restate the idea in your own words (what you understand,
   what you're assuming) plus numbered clarifying questions for anything genuinely ambiguous, and
   wait for the user's reply. Continuations skip this entirely.

3. Improve the raw task into a real prompt: imperative and actionable; scope stated explicitly
   (in and out, with the *why* behind non-obvious constraints); dependent steps ordered; expected
   output format stated. Never include "commit this": the container's deny-list blocks it, and
   changes stay as uncommitted diffs for the user. Pick the model tier: `planning` for
   design/plan work, `impl` for code changes of substance, `quick` for small tasks (default when
   ambiguous; ask if truly unclear). If information is missing, stop and ask; never silently
   assume or invent a requirement to make the prompt "complete".

4. Show the parsed project, branch, the improved prompt and the chosen tier, and get explicit
   confirmation. Never fire on a guessed parse.

5. Once confirmed, run exactly (shell-quoted, with a hard client-side timeout so a hung call
   can't run forever):
   `ssh -i <KEY> -o BatchMode=yes <DEV> "START::PROJECT::BRANCH::MODEL::TASK"`
   Always pass MODEL explicitly.

6. After START returns a ticket, register the one-shot finalize watcher. Copy this template
   verbatim, substituting only the ticket id. Use a literal command payload, never a free-form
   instruction the scheduler's agent must interpret (improvised payloads are how finalizes get
   lost), and always set the job timeout well above the longest plausible task (schedulers kill
   jobs at a default timeout, and this trigger blocks for the container's entire runtime):

   ```
   automations add --name "finalize: <ticket>"
     --on-exit "ssh -i <KEY> -o BatchMode=yes <DEV> \"docker wait work-<ticket>\""
     --command "ssh -i <KEY> -o BatchMode=yes <DEV> \"WAIT::<ticket>\""
     --announce --channel <your-channel> --to <CHAT>
     --delete-after-run --timeout-seconds 14400
   ```

   The `--on-exit` trigger must run `docker wait` ON the dev machine (via SSH). Docker lives
   there, not here.

7. Relay the dispatch result to the user **raw and unedited**: they are reviewing real code
   changes and need the complete picture. If a run is killed or times out, report that plainly as
   partial/failed; never claim success on a killed run.

8. Never run any other shell command as part of this flow.

**Standing watchdog - do not touch.** A permanent automation runs `SWEEP::` on the dev machine
every 3 minutes, independent of step 6. It finalizes any ticket whose container exited
unreported and flags long runs. Never disable, delete or edit it; it is the fallback for exactly
the failure modes step 6 is prone to.

## Feature lifecycle (vocabulary, not law)

Stages for substantial feature work. **The user decides which stages a given piece of work
deserves.** Never refuse or stall a dispatch because a stage was skipped; if skipping one carries
real risk, suggest it in ONE line at confirmation time and let the user decide.

1. BRAINSTORM (`planning`): explore idea, options, trade-offs; no code.
2. SCOPE REVIEW (`planning`): verify the idea's assumptions against the real code.
3. PHASED PLAN (`planning`): independently dispatchable phases; open decisions as numbered questions.
4. PRESSURE-TEST (`planning`): optional multi-model review of the plan, when asked.
5. PHASE 1..N (`impl`): one dispatch per phase; the mandatory finish-up runs remote-side.
6. REVIEW PASSES: the named reviews below, whichever the user picks.
7. TEST LIST (`planning`): exhaustive scenario list, generation only.
8. CLOSEOUT: final dispatch to consolidate notes, update project skills, confirm both in output.

When drafting a stage's prompt, tell the work agent to record in its project NOTES.md which stage
finished and what the next dispatch should be.

## Named review dispatches

On request by name, skip echo-back, use the canned prompt (plus project/branch), run the normal
confirm-then-dispatch flow. `impl` for a large diff, `quick` for a small one. All findings-only,
no code changes:

- **Quality review**: the branch's full diff line by line, fixed question order: (1) optimized?
  (2) secure? (3) over-coded, i.e. same result with less code? (4) matches what was asked and
  planned (check NOTES.md)? Report every finding including low-severity/uncertain, confidence
  noted.
- **Pattern alignment**: diff vs. the project's own conventions; every deviation must cite the
  existing file:line showing the pattern to follow.
- **Blast-radius audit**: the diff vs. documented module/context boundaries; report anything the
  change could break outside the feature, with evidence.

## Test-list dispatch (generation only)

On request, dispatch `planning`: generate an exhaustive manual-test scenario list covering every
possible usage INCLUDING wrong usage (invalid input, out-of-order actions, permission edges,
concurrency), double-check it against the branch diff for missing cases, extract open product
decisions as numbered questions, deliver in the output AND persist to the project NOTES.md. Hard
boundary: the work agent never executes tests, opens browsers, or touches a running app.

## Usage-limit recovery

If a relayed result contains the agent provider's "limit reached · resets <time>" message: tell
the user immediately (never let it read as a stalled run); schedule a one-shot retry after the
reset time plus a 15–30 min buffer (the reported timezone may not be yours); the retry re-runs
the same project+branch+tier with a short "continue exactly where you left off" task, since
session continuity carries the rest. No new confirmation needed (completion of an approved task),
but register its own finalize watcher as usual, and tell the user every time this loops.

## Closing out a feature

Only when the user explicitly says a feature/branch is done: dispatch one final task on the same
project+branch asking the work agent to (1) consolidate a clean end-to-end summary into the
project NOTES.md, (2) update any project-context skill whose description the work made
inaccurate, (3) confirm both in its output. Never guess that a feature is finished.
