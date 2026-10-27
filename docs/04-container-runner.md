# 04 - Container runner

The dispatch script is the only code that runs on the dev machine's SSH boundary, so it carries
most of the pipeline's engineering. This doc describes its **contract**: if you port it off
PowerShell (the [template](../templates/dispatch.ps1) is Windows PowerShell 5.1), keep every
invariant here and validate with the acceptance tests at the bottom.

## What START does

1. **Resolve the project** by name under a fixed set of root folders (direct match first, then a
   bounded recursive search that only accepts directories containing `.git`). Ambiguity is an
   error, not a guess.
2. **One git worktree per branch** under a dedicated worktree root. Reused across dispatches.
   Edge case that must be handled: if the requested branch is currently checked out in the main
   project folder, git cannot check it out twice. Work directly in the main folder and say so
   loudly in the output.
3. **Write the task to a per-ticket file** and mount it read-only into the container. The task
   text must never cross a native-process argv boundary on Windows: PowerShell 5.1 silently
   mangles arguments containing embedded double quotes, which once delivered a truncated task to
   the container while every log on the way looked correct. A file sidesteps the whole class:
   any characters are safe, and the container reads it with `$(cat /run/task.txt)`.
4. **Map the model tier** to a concrete model id and launch detached:

```
docker run -d --name work-<ticket>
  -v <worktree>:/workspace
  -v <settings.json>:/etc/claude-settings.json:ro
  -v <memory mounts>            (see 06-memory.md)
  -v <session dir>:/root/.claude
  -v <task file>:/run/task.txt:ro
  -v <launcher>:/run/launch.sh:ro
  -e CLAUDE_CODE_OAUTH_TOKEN=<read from a permissions-restricted file>
  -e WORK_MODEL=<model id>  -e WORK_EFFORT=high
  -w /workspace --entrypoint sh  <image>  /run/launch.sh
```

5. **Persist ticket metadata** (worktree path, project, branch, model) to a small JSON file,
   which is what WAIT/STATUS/SWEEP operate on later, and print the ticket id.

## Model tiers

The MODEL field in the protocol is a *tier*, not a model id. The mapping lives in the script, so
upgrading models never requires touching the gateway's manual:

| Tier | Meant for | My current mapping |
|---|---|---|
| `planning` | plans, specs, architecture, scenario lists; no code changes | the strongest reasoning model available |
| `impl` | code changes of any substance | a top coding model |
| `quick` | small edits, lookups, one-file touch-ups (and the default) | a fast/cheap model |

A raw model id passes through untouched, so one-off experiments don't need a script change.

## Session continuity

Each project+branch gets a persistent session directory mounted as the agent's config/state dir,
and the launcher starts the agent with its "continue previous conversation" flag. Consecutive
dispatches on the same branch therefore **resume the same conversation**: phase 2 remembers
phase 1's plan without re-reading anything. Safe on first use: continuing an empty session just
starts fresh. Continuity deliberately does *not* cross branches or projects; durable knowledge
belongs in the memory repo ([06](06-memory.md)), not in a chat transcript.

## The sandbox

The image is minimal: a slim Node base plus git and the coding agent CLI
([templates/Dockerfile](../templates/Dockerfile)). The real fence is the agent's own settings
file, mounted read-only ([templates/claude-settings.json](../templates/claude-settings.json)):
broad tool allows for working, plus a deny-list:

```
git commit / git push / PR creation / rm -rf / sudo
```

The agent works at full permissiveness *inside* the sandbox (headless mode can't answer
permission prompts anyway) while the few actions that would make its changes permanent, or
destructive, are denied outright. Combined with the container seeing only one worktree, the
worst realistic outcome of a bad run is a messy diff you reject.

Secrets: the API/OAuth token is read from a file with restricted permissions at launch and
injected as an environment variable. It never appears in the script, the ticket files, the logs
or the gateway's side of the conversation.

## What WAIT / SWEEP finalize

Finalize = full `docker logs` of the run, `git status --short` of the worktree (the "here's what
to review" summary), commit of the memory repo if the agent wrote notes, container removal,
ticket-file cleanup. One hard-won rule: **any network operation inside finalize gets a hard
timeout**. Finalize runs inside a forced-command SSH session where at least one tool (git's
spawned ssh, in my case) can deadlock indefinitely, and an unbounded hang there cascades into the
reliability layer. Bound it, report the timeout, and let a scheduled catch-up task (mine runs
daily) retry the non-critical part.

## Acceptance tests for a port

Run all of these before trusting your version:

1. **Hostile task text:** dispatch a task containing double quotes, `$variables`, backticks and a
   literal `$(reboot)`. The container's `/run/task.txt` must match byte-for-byte, and nothing
   must execute.
2. **Branch already checked out:** dispatch onto the branch your main folder has checked out.
   It must warn and reuse the folder, not fail or double-checkout.
3. **Unknown project / ambiguous project:** both must error without launching anything.
4. **Continuity:** two dispatches on one branch; the second must demonstrably remember the first.
5. **Finalize with a dead network:** finalize must complete (with a NOTE) even when the memory
   push can't reach the remote.

## ⚠ Decisions you must make

1. Project roots: which folders the script may resolve projects under. This is also a boundary;
   nothing outside them can ever be dispatched on.
2. Your tier→model mapping and the default tier.
3. What the deny-list blocks for *your* agent CLI. Commit/push/sudo/destructive-delete is the
   floor; add whatever else your stack makes dangerous.
4. Whether your dev machine can even run this when you're away (power/sleep settings, container
   runtime starting on boot). A pipeline whose runner is asleep delivers nothing.

Next: [05 - Reliability](05-reliability.md)
