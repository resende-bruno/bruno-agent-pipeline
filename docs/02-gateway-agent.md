# 02 - Gateway agent

The gateway is a small always-on agent whose whole job is **translation and discipline**: turn a
casual chat message into a well-scoped prompt, get your confirmation, fire exactly one templated
SSH call, and relay the result untouched. It never writes code and never explores your dev
machine.

## Platform

I run [OpenClaw](https://openclaw.ai) in a container on a cheap VPS. Any platform works if it has
these four capabilities; they are the actual requirements:

1. **A messaging bridge** to a channel you'll really use from your phone.
2. **Controlled shell execution**, ideally an allowlist/approval system where a command pattern
   can be pre-approved and everything else requires explicit human approval.
3. **A scheduler** ("automations", cron-like) able to run a literal shell command at/after an
   event, announce output to your channel, and delete itself after running.
4. **A persistent instruction file** the agent reloads per session (OpenClaw calls it
   `AGENTS.md`). This is where the whole dispatch behavior is written down.

On the channel choice: I use Telegram simply because I don't use Telegram for anything else, so
the agent lives in a dedicated app with its own notification stream and zero chance of mixing
with human conversations. Pick whatever channel gives *you* that separation.

## The manual is the product

Everything the gateway does well, it does because its instruction file says so explicitly; see
the sanitized [templates/AGENTS.md](../templates/AGENTS.md) for the full illustrative version.
The load-bearing rules, and why they exist:

- **A dispatch message is ALWAYS a new dispatch.** Never a cue to investigate what happened to a
  previous ticket. We added this after the agent once misread a new request as "recover the
  previous ticket" and produced a string of denied exploratory commands instead of a dispatch.
  Agents fill ambiguity with initiative; this rule removes the ambiguity.
- **Confirm before firing.** The agent shows parsed project, branch, the *improved* prompt, and
  the chosen model tier, then waits. Nothing dispatches from a guessed parse.
- **Improve the prompt, don't just forward it.** The chat message is shorthand; the container
  gets a real prompt: imperative, scoped (in/out of scope, with the *why* behind constraints),
  dependent steps ordered, expected output stated, and tuned to the model tier it will run on.
- **Echo-back for new ideas.** If the message introduces a new feature or scope change, the agent
  first restates the idea in its own words plus numbered clarifying questions, and only drafts a
  prompt after you answer. Continuations ("start phase 2") skip this; the protocol must never
  add friction to the fast path. More in [07 - Workflow layer](07-workflow-layer.md).
- **Scheduler payloads are literal templates.** The finalize watcher the agent registers after
  each dispatch is a copy-paste command template with exactly one substitution (the ticket id).
  Every mechanism where the agent had to *construct* a payload at runtime eventually produced a
  malformed one; the template approach has produced zero.
- **Relay results raw.** Output of a dispatch is never summarized: you are reviewing real work,
  you need the complete picture. (Everything else the gateway reports *is* summarized; the
  exception is deliberate and scoped.)

## Locking the gateway down

The gateway needs exactly one remote capability: the dispatch SSH call. Give it that and nothing
more.

- Pre-approve one **exec allowlist pattern** matching the full invocation: the ssh binary, the
  dedicated key path, batch mode, the specific `user@dev-machine`, and a payload anchored to the
  four protocol verbs. One gotcha worth inheriting: match against what your platform actually
  compares. OpenClaw, for instance, matches a *parsed argv joined by spaces*, with shell quotes
  already stripped, so a pattern expecting literal quote characters never matches. Test the
  allowlist with a real dispatch before trusting it.
- Everything outside the pattern stays on human approval. The first time the agent improvises a
  command, you'll see it as an approval request instead of an execution.
- Keep the gateway's workspace clean. Stray files in its home directory become "context" that can
  derail behavior in creative ways; treat its workspace as config, not as a scratch area.

## Secrets hygiene (applies to the whole pipeline)

- The SSH private key is generated **for this purpose only**, stored only in the gateway's
  key directory with correct permissions, and never reused for anything else.
- Never paste keys, tokens or passwords into the chat channel, into the agent's instruction
  files, or into any terminal the agent logs. Put secrets in files with tight permissions and
  reference them by path. Assume anything typed near an agent ends up in a transcript.
- The coding agent's API/OAuth token lives in a file on the dev machine, readable by the dispatch
  script, injected into the container as an environment variable. The gateway never sees it.

## Session hygiene

Two operational facts that will bite you if unknown:

- A live agent session **keeps the instruction file and model from when the session started**.
  After editing the manual or changing the model, reset/delete the active session so the next
  message boots fresh.
- Long chat sessions degrade: context costs grow and the agent's attention dilutes. Give the
  gateway an explicit rule to periodically flush durable facts to its memory files and compact
  its own session (the template manual includes one).

## ⚠ Decisions you must make

1. Gateway platform and where it runs. VPS size: this is a coordinator, not a worker, so small is
   fine; it should be a machine you're comfortable rebuilding from notes.
2. Messaging channel, ideally one you can dedicate to the agent.
3. Which model powers the gateway. It needs reliable instruction-following over long rule files
   more than raw coding power; a mid-tier model from a major provider is the sweet spot.
4. Your approval posture: which single command pattern gets pre-approved, and the discipline that
   *everything* else stays human-approved.

Next: [03 - Dispatch channel](03-dispatch-channel.md)
