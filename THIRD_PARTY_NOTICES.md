# Third-party notices

## fusion360-mcp-server

Forked from [faust-machines/fusion360-mcp-server](https://github.com/faust-machines/fusion360-mcp-server), **MIT**.

Local additions: photoreal render tools (`start_render`,
`get_render_status`, `set_scene_environment`), drawing tools
(`create_drawing`, `export_drawing_pdf`), `fetch_api_doc`, plus fixes to
`delete_all` and `create_box_parametric` and raised timeouts.

Preserve the upstream copyright notice in any redistribution.

## Ideas adopted from other work

- [frankhommers/autodesk-fusion-mcp](https://github.com/frankhommers/autodesk-fusion-mcp) (**MIT**) — the preview-flagged
  documentation lookup, adopted in spirit as `fetch_api_doc`
- [Poyraxx/fusion-advanced-mcp-server](https://github.com/Poyraxx/fusion-advanced-mcp-server) (**GPL-3.0**) — the prebound
  `execute_code` context (finders, unit helpers, `state` dict) was
  **studied, not copied**. No GPL-3.0 code is included in this repository.

## Autodesk

Autodesk Fusion and its API are © Autodesk, Inc. `adsk.drawing` is
**preview API**; Autodesk states it may change without a deprecation period
and should not be used in distributed programs. Not affiliated with or
endorsed by Autodesk.

## NVIDIA

NemoClaw, OpenShell and Hermes are © NVIDIA Corporation. Not affiliated with
or endorsed by NVIDIA.
