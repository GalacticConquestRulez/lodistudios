# WebPro — mark-up and in-preview editing

Asked for on 2026-09-18: *"visuals, drag and drop edits, in preview text editing, maybe highlight
text etc. I want to make write ups as easy as possible to mark attach a note that the AI looks
for and reads."*

## The mechanism: Marks and the Brief
Every gesture in the preview produces a **Mark** — a structured note: page, element (selector
and source file:line), screenshot crop, computed styles, what it was, what is wanted, who made
it, when. Marks accumulate into a numbered **Brief**. Every run reads the Brief first and must
answer each item; the report ticks them off; the client PDF is generated from the answers.

The preview runs the site with source locations on every element (dev-mode source maps, or a
build step that stamps `data-lodi` attributes), so a pin resolves to code, not pixels. The
overlay is one injected script, built once as a standalone library and vendored into both
LodiStudios and Green Flash Studio — no runtime dependency between the two products.

## Features
**Marking up**
1. Pin & note — click an element, numbered pin, typed note; carries selector, crop, styles.
2. Highlight to edit — select text; type the replacement in place or pick a rewrite preset
   (shorter / warmer / in the client's voice, from the Playbook). The AI receives an exact diff.
3. Voice marks — hold a pin and talk (phone); transcribed and attached.
4. Scribble on a screenshot — draw on any screenshot; scribbles map back to page elements.
5. Sticky notes the AI always reads — persistent, page- or section-pinned Playbook rules
   ("client wrote this, never rewrite"; "hero Mavic stays purple"), injected into every run
   touching that page.

**Editing in place**
6. Drag to reorder sections — the Mark records the structural move; the AI applies it in code.
7. Drop media — photo onto an image slot: upload, resize, swap, alt text drafted; PDF onto a
   section: linked; logo into the footer.
8. Style knobs on selection — size, colour (site tokens only), spacing, radius; arrow-key nudges;
   each nudge is a Mark, committed as one run.
9. Copy deck — every string on every page as one searchable document; edit inline; the AI
   applies to code. The write-up tool.

**Seeing what changed**
10. Before / after per page — visual diff with changed regions highlighted, slider, accept or
    revert per page; screenshots attached to the run report.
11. Time-travel scrubber — scrub through commits with the preview live; one-press restore.
    (backups-not-gates, made visual)
12. Try three — right-click a section; three AI variants rendered side by side; pick one;
    nothing written until chosen.

**Closing the loop**
13. Client marks — a share link; the client pins and notes without a login; their Marks join
    the Brief. Belongs in the licensed studio as well.
14. Brief → run → checklist → client PDF, generated from the run's per-item answers.

## Order
Pins, highlight-to-edit and the Brief first (they are the mechanism); then drop media, drag to
reorder, before/after; then copy deck, sticky notes, time-travel; then voice, scribble, try
three, client marks.
