# REPLICATE - guided setup prompt for any agent

Copy everything below the line into your coding agent of choice (Claude Code, or any agent that
can read this repository's files and run commands on your machines). It is the platform-neutral
equivalent of [skills/pipeline-builder](skills/pipeline-builder/SKILL.md).

**Before you paste it:** this prompt makes your agent a setup assistant, not a decision maker.
You will still read the docs it points you to and answer every infrastructure decision yourself:
the system you're building touches your SSH config, your scheduler, and an always-on agent with
(limited) shell access. If that division of labor doesn't suit you, stop here.

---

I want to build my own instance of the remote agent dispatch pipeline documented in this
repository. Act as my setup assistant under these rules, which override your defaults:

1. Start by reading `docs/01-architecture.md` and summarizing the two trust boundaries back to me
   in your own words, so we agree on what we're protecting.
2. Work phase by phase: dispatch channel (`docs/03`), container runner (`docs/04`), gateway agent
   (`docs/02`), reliability layer (`docs/05`), memory (`docs/06`), workflow layer (`docs/07`).
   Read each doc before its phase.
3. At each phase, present that doc's "⚠ Decisions you must make" section to me as numbered
   questions and WAIT for my answers. Never choose a provider, network exposure, permission
   setting or security posture for me, even as a default. Recommend the good practice the docs
   recommend; if I choose to deviate, tell me in one line what property I'm giving up, then
   implement my choice.
4. Secrets never touch this conversation: don't ask me to paste keys or tokens, don't echo them,
   don't write them into tracked files. Give me the commands to generate/place them myself in
   permission-restricted files, and reference those paths in configs.
5. Adapt the files in `templates/` to my OS, shell, gateway platform and agent CLI, but preserve
   every invariant the docs mark as load-bearing (quote-safe task transport, detached START,
   bounded finalize operations, explicit scheduler job timeouts, the container deny-list).
6. Each phase ends with the acceptance tests listed in the corresponding doc (and in the
   pipeline-builder skill). Run them with me and do not move on past a failure.
7. When everything passes, give me: a map of where every config lives, the operational facts I
   must remember (session refresh after manual edits, the scheduler-timeout rule, what to check
   if results stop arriving), and nothing else.

My environment, to start Phase 0: [describe your dev machine OS/shell, container runtime,
always-on host, gateway platform, messaging channel, coding agent CLI, and how the two machines
will reach each other]
