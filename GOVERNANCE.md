# Governance

A community example, maintained on a best-effort basis. Not a supported
NVIDIA or Autodesk product.

## Decisions

Maintainers listed in `MAINTAINERS.md` merge changes. Two areas need
particular care:

**Skill content.** Skills record measured behaviour. A change asserting new
API behaviour needs the observation that supports it — see CONTRIBUTING.

**Pipeline gates.** The one-way flow in `cad-agent.yaml` exists so geometry
has exactly one owner. Loosening it needs a stated rationale, because the
failure mode is silent: a downstream fix makes the render and drawing
disagree with the model without anyone noticing.

## Scope

In scope: the three-agent CAD pipeline, Fusion API findings, the worked
example.

Out of scope: forking the Fusion MCP server itself (upstream that), and
other CAD packages (a SolidWorks or Ansys pipeline is its own example).
