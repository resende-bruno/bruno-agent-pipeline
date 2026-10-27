# Working conventions for the work agent (template)

Mounted as `/mem-shared/CLAUDE.md` into every work container. These are the rules the coding
agent follows in every dispatch, regardless of project.

## Memory locations
Three memory directories are mounted alongside the project worktree at /workspace:
- /mem-project/ : notes for *this* project only. Main file: /mem-project/NOTES.md
- /mem-root/    : notes shared across every project under this root folder
- /mem-shared/  : notes and skills that apply universally (this file lives here)

## Always write a findings summary
At the end of every task (analysis, implementation, investigation), append a short summary to
/mem-project/NOTES.md: what was asked, what was found or decided, what was changed (files/lines),
and anything a future task on this project would need. Do this unconditionally. A later dispatch
has no access to this conversation unless it's on the same branch; NOTES.md is the only
continuity across branches. Keep it terse: bullets, not prose.

## Session continuity across dispatches on the same branch
Consecutive dispatches on the same project and branch resume the same conversation, so you may
genuinely remember earlier prompts on this branch. This does NOT extend across branches or
projects. If a prior turn already established something (a plan, file/line references, a
decision), trust it; never silently guess or fabricate context you don't actually have.

## Verify before reporting success
"Saved" or "done" in a reply is not proof. Before stating something was written or changed,
confirm it by reading the file back or checking git status, not by trusting your own prior tool
call. If you cannot verify, say so explicitly.

## Cite the source for every factual claim about existing code
When you assert how something behaves or why it is the way it is, point at the actual file:line.
"X happens because Y calls Z at file.cs:42" is verifiable; "X happens because of the validation
logic" is not, even if true. Applies to NOTES.md summaries, review findings, and everything you
report back.

## Maintain a project glossary in CONTEXT.md
When a name in a task doesn't match reality (a field, table or concept actually called something
else, split differently, or narrower/broader than assumed), append it to /mem-project/CONTEXT.md
as `term: what it actually means (and what it's not)`, immediately. CONTEXT.md is a glossary and
nothing else: never a spec, scratchpad or implementation log.

## When reviewing code, separate two independent questions
Report under separate headings, since one can mask the other:
- **Standards**: does this violate the project's own conventions or a general code smell?
- **Spec**: does this do what was asked, or are there missing requirements, scope creep, a
  misunderstanding?
Before reviewing, pin the exact comparison point (commit/branch/phase) and identify what the
"spec" is: an explicit reference in the task, a plan already in NOTES.md, or ask.

## Mandatory finish-up for every implementation dispatch
Whenever the task changed code (analysis/planning/review-only tasks exempt), run this self-pass
over your OWN diff (`git diff`, only what this dispatch changed) before the final output, and
act on what you find:
1. **Comment hygiene**: strip comments you added that a competent reader doesn't need. Keep only
   comments stating a constraint the code can't show.
2. **Code cleaning**: dead code, unused imports/variables, leftover scaffolding from your work.
3. **Optimization**: anything obviously wasteful in the touched paths.
4. **Security**: injection, unvalidated input at trust boundaries, permission gaps in the
   touched paths.
5. **Over-coding**: can the same result be achieved with less code? Simplify where yes.

End the final output with one line per check: what was found and changed, or "nothing". Do NOT
generate a commit message; the user writes those by hand. This self-pass covers your own diff
only; branch-wide review passes arrive as their own separate dispatches.
