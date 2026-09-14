# Security

## Reporting

Report vulnerabilities privately via GitHub Security Advisories. Do not open
a public issue.

## Threat model

This example gives an agent **arbitrary code execution inside a desktop CAD
application** via `execute_code`. That is the whole point of the tool and it
is not something to be casual about.

- `execute_code` runs unsandboxed Python in the Fusion process, with full
  filesystem access as the logged-in user
- The add-in listens on `127.0.0.1:9876` with **no authentication** — any
  local process can drive Fusion
- `policy.yaml` restricts sandbox egress, but the host MCP is outside that
  boundary by design

Do not expose port 9876 beyond loopback. Do not run this on a host holding
CAD data you cannot afford to lose — the agent can delete bodies and
overwrite documents.

## Autodesk's own endpoint

`127.0.0.1:27182` is deliberately excluded from `policy.yaml`. It is
localhost-only and unauthenticated. This example does not use it, and the
exclusion is documented in `plugins/fusion-mcp/README.md`.

## Data

Renders and drawings are written to `FUSION_OUTPUT_DIR` on the host. Design
files may sync to Autodesk cloud storage — drawing creation **requires** a
cloud `DataFile`, so anything you draw has left the machine.
