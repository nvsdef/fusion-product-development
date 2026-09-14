# Contributing

## Before you open a PR

```bash
python3 scripts/setup/sync_shared_skills.py   # must report 0 updated
python3 scripts/setup/verify_layout.py        # must exit 0
```

## Shared skills

`fusion-mcp-core` is required by all three agents. Skills are per-agent in
this layout, so the canonical copy lives in `agents/cad-engineer/skills/` and
`sync_shared_skills.py` fans it out.

**Edit `agents/cad-engineer/skills/`, the single copy.** A PR that changes an
agent copy directly will be reverted by the next sync.

## Writing skills

Skills in this repo record **measured behaviour**, not documentation. The
standard is:

- If you write "X does Y", you observed X doing Y in a live session
- Include the number you measured, not an estimate
- If a documented API behaves differently from its docs, say so and give the
  observed behaviour
- If a tool reports success while doing nothing, that goes in a table with
  what it *claimed* and what it *did*

Anything inferred rather than observed should be labelled as such.

## Writing agent SOUL.md

State the mission, the load-order of skills, the working rules, and an
explicit exit gate. Include an honesty section — what the agent should admit
it cannot do rather than working around silently.

Downstream agents must be told not to edit geometry and to report defects
upstream. See `harnesses/hermes/README.md`.

## Reporting a Fusion API finding

Open an issue with:

1. The exact call and arguments
2. What it returned
3. What actually happened to the model (volume/face-count/bbox before and
   after)
4. Fusion version

The gap between (2) and (3) is the finding. Several entries in
`fusion-mcp-core` exist only because someone checked (3) instead of trusting
(2).
