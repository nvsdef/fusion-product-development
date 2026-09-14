---
name: Bug report
about: Something behaves differently from what the skills say
labels: bug
---

## What happened

## What the skills say should happen

Quote the relevant line from the skill file.

## Evidence

A tool returning `success: True` is not evidence. Include the independent
measurement:

```
volume before / after :
face count before / after :
bbox before / after :
```

## Environment

- Fusion version:
- fusion-mcp-server commit:
- Timeouts (`_TIMEOUT`, `submit`):
- OS:

## Checked first

- [ ] Scripts and Add-Ins dialog closed
- [ ] `get_scene_info` succeeds (not just `ping`)
- [ ] `~/fusion360mcp.log` reviewed
- [ ] Not a retry after a timeout (which runs the call twice)
