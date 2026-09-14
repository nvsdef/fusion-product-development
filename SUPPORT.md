# Support

## First, check these

Most failures are one of these six, in order of frequency.

| Symptom | Cause | Fix |
|---|---|---|
| Every API tool times out, `ping` works | Scripts and Add-Ins dialog is **open** — modal, blocks the main thread | Close it |
| No tools at all in the client | Add-in not running | Fusion > UTILITIES > Scripts and Add-Ins > Run |
| `ping` fails but port 9876 is open | client-side MCP process is stale | Quit the client from the **system tray** and relaunch |
| Everything is 10× too big or small | display-units trap — a bare number in an expression | Unit-qualify: `"40 mm"` |
| `create_drawing` fails around 30 s | timeouts not raised | `scripts/setup/patch_timeouts.py` |
| `DESIGN_NOT_SAVED` | drawings need a cloud `DataFile` | Ctrl+S in Fusion, wait for sync |

## Diagnostics

```
~/fusion360mcp.log                          # add-in log; read this first
Test-NetConnection 127.0.0.1 -Port 9876     # socket
get_scene_info                              # NOT ping
```

Ask for `1 + 1` via `execute_code` after any timeout. If it succeeds, the
previous payload was too large — do **not** retry the original call.

## If Fusion freezes

1. `Get-Process Fusion360 | Select CPU, PM, Responding` twice, 30 s apart
2. CPU climbing → still working, wait
3. CPU flat and PM very high (>10 GB) → thrashing, unlikely to recover
4. `Stop-Process -Name Fusion360 -Force`, relaunch, accept the recovery prompt

Then check for duplicated sketches (`SK_Name (1)`, `(2)`) before doing
anything else — a timed-out call that was retried will have run more than
once.

## Channels

Open a GitHub issue using the templates in `.github/ISSUE_TEMPLATE`.
