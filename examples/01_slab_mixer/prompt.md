# Run prompt - SLAB

Attach `docs/SLAB_PRD_RevC.pdf` and the two mockups in `reference/`.

## LOCKED - do not shorten

Hermes builds its task widget by decomposing **this prompt**. Its planner runs
before any skill file is read, so it cannot see `slab-run`. The numbered stage
list below is the only thing that produces the widget, and it has been deleted
twice while making the prompt read better - both times the tasks disappeared.

Everything else lives in the skills. The document name is derived by the agent.

---

Build SLAB - a portable 6-channel production mixer and USB-C audio interface -
in Fusion 360 from the attached product design brief and concept mockups.

Work these stages in order:

1. Save to the cloud
2. Gate the document
3. Build the twelve feature classes, 1 to 12, one `execute_code` call each
4. CMF - ten appearances, configured then assigned
5. Viewport check and layout checks
6. Switch to the Render workspace and calibrate exposure
7. Two final renders
8. Composite and compare against the mockups
9. Line-art views, the A3 general arrangement sheet, then the drawing
10. Verification report

End every stage with one line of measured values: `STAGE n · ... · PASS`.
