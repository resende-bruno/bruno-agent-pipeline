# 06 - Memory

Each dispatch is a fresh process on a possibly-fresh branch. Without a memory design, every task
re-discovers the project from zero and repeats old mistakes. The pipeline uses two mechanisms with
a sharp division of labor.

## Mechanism 1 - session continuity (cheap, automatic, narrow)

Covered in [04](04-container-runner.md): same project + same branch = same resumed conversation.
Perfect for multi-phase features: phase 3 remembers the plan, the decisions and the code written
in phases 1–2 with zero effort. Its limits are the point: it does not cross branches, does not
cross projects, and a transcript is not a knowledge base. Anything that should outlive the branch
must graduate to mechanism 2.

## Mechanism 2 - the memory repo (durable, versioned, structured)

A dedicated git repository on the dev machine, mounted into every container in three slices:

```
memory/
├── _shared/            → /mem-shared    conventions + skills for every task, always
│   ├── CLAUDE.md         the agent's own working rules (see template)
│   └── .claude/skills/   reusable skills, auto-discovered by the agent
├── _<root>/            → /mem-root     context shared by all projects under one root folder
└── <project>/          → /mem-project  notes for this one project
    ├── NOTES.md          running log of findings and decisions
    ├── CONTEXT.md        glossary (and nothing else)
    └── .claude/skills/   project-specific skills
```

Being a git repo is load-bearing: history shows *when* the agent learned something, bad notes can
be reverted, and the whole thing is recoverable. It's also the **only repository the agent may
commit to**. The dispatch script commits it deterministically at finalize (the agent doesn't run
git for this either; it just writes files).

## The conventions that make it work

These live in [`_shared/CLAUDE.md`](../templates/memory-repo/_shared/CLAUDE.md); the agent reads
them in every container. The ones that earn their place:

- **Always write a findings summary** to the project's NOTES.md at the end of every task, asked
  or not: what was asked, what was found/decided, what changed (files/lines). A later dispatch
  on another branch has no transcript access; NOTES.md is the only cross-branch continuity.
- **Cite file:line for every factual claim about code.** "X because Y calls Z at `file.cs:42`" is
  verifiable; "X because of the validation logic" is not. This single rule is the difference
  between notes a future task can trust and plausible-sounding residue.
- **CONTEXT.md is a glossary, updated the moment a term resolves.** When a name in a task turns
  out to mean something else in the real codebase, that mapping gets one line, immediately, so
  no future dispatch re-derives the same wrong assumption. A glossary that's also a scratchpad is
  neither.
- **Verify before reporting success.** "Saved" in a reply is not proof; the agent re-reads the
  file or checks git status before claiming a write happened.
- A `next dispatch:` pointer at the end of NOTES.md tracks where a multi-phase feature stands.
  The gateway's prompts tell the agent to maintain it ([07](07-workflow-layer.md)).

## What the human owns

The memory repo is agent-written and agent-committed. The **project repos are the mirror
opposite**: the agent's deny-list blocks commit/push there entirely, and the human reviews the
diff and commits by hand. Keep the asymmetry clean: the moment an agent can commit "just this
once" to a project repo, the review gate is gone.

Same for anything stateful outside git: database schema changes, migrations, config on real
environments. Dispatches produce the *code/scripts* for those; applying them is a human action.

## ⚠ Decisions you must make

1. Where the memory repo's remote lives (private hosted repo is fine; it will contain your
   project vocabulary and decisions, so treat its visibility accordingly), and which credentials
   push it. A dedicated deploy key, used for nothing else, is the clean answer.
2. Your root-folder slicing (`_shared` / per-root / per-project); mirror how your own projects
   group.
3. How much of your team's context belongs in agent memory at all, if you work on an employer's
   codebase. Notes describing proprietary internals deserve the same confidentiality decisions
   as the code itself.

Next: [07 - Workflow layer](07-workflow-layer.md)
