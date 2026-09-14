#!/usr/bin/env bash
# Host co-processes in tmux. Far simpler than the CAE example: there is no
# CFD solver, no WebRTC viewport and no streaming -- Fusion's own GUI is the
# viewport, and rendering happens inside Fusion on the host GPU.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f .env ] && set -a && . ./.env && set +a || true

S=cad
tmux has-session -t $S 2>/dev/null && { echo "session '$S' exists; attach with: tmux attach -t $S"; exit 0; }

tmux new-session -d -s $S -n fusion-mcp
tmux send-keys -t $S:fusion-mcp "echo 'fusion-mcp is launched BY THE CLIENT over stdio.'; echo 'Nothing to start here -- this pane is for tailing the add-in log.'; tail -f \"\$HOME/fusion360mcp.log\" 2>/dev/null || echo 'log appears once the add-in runs'" C-m

tmux new-window -t $S -n socket-check
tmux send-keys -t $S:socket-check "echo 'Add-in socket check (expect TcpTestSucceeded: True):'; echo '  Test-NetConnection 127.0.0.1 -Port 9876'" C-m

echo "tmux session '$S' started. Attach: tmux attach -t $S"
echo
echo "REMINDER: launch Fusion by hand, Run the Fusion360MCP add-in,"
echo "and CLOSE the Scripts and Add-Ins dialog."
