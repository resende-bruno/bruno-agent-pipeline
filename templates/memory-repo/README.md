# Memory repo (template)

Skeleton for the agent-memory git repository (docs/06). Mounted into every work container by the
dispatch script:

- `_shared/` → `/mem-shared`: conventions (`_shared/CLAUDE.md`) and skills that apply to every
  task, always loaded
- `_<root>/` → `/mem-root`: context shared across all projects under one root folder (create one
  per entry in the dispatch script's root map)
- `<project-name>/` → `/mem-project`: notes for one project: `NOTES.md` (running findings log),
  `CONTEXT.md` (glossary only), `.claude/skills/` (project-specific skills, auto-discovered)

Keep this repo **private**: it will accumulate your projects' vocabulary and decisions. Push it
with a dedicated deploy key used for nothing else.
