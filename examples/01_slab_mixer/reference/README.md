# Reference imagery

`reference-match-loop` matches the build against whatever is in this folder.
Without an image the agent builds to the brief and reports that it had nothing
to compare against — it does not guess.

**Drop the mock-up renders here under any filename.** The loop enumerates the
directory and reads every image it finds — `.png`, `.jpg`, `.jpeg`, `.webp` —
so there is nothing to rename. Whatever your image tool called the file is fine.

Several images are treated as **different views of the same product**, not as
alternatives to choose between. The agent reconciles them against each other and
reports which files it used.

## What the loop does with it

Judge layout on a **top-orthographic** view, never a perspective pass. An
isometric projection makes a constant-X column look diagonal and foreshortens
the graduation arcs into what reads as scatter — that misreading produced a
defect report that had to be withdrawn.

Colour and exposure are judged numerically, not by eye. The acceptance figures
are in `../expected.md`; the sampling method (a stdlib PNG decoder, since
Fusion's Python has no PIL) is in
`../../../agents/cad-engineer/skills/fusion-photoreal-render/SKILL.md`.

## Note on this repo

The reference render used to develop this example is not committed — it is
product imagery, and `.gitignore` excludes `*.png` outside `docs/`. Supply your
own before the first run.
