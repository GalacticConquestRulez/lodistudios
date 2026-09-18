# LodiStudios — feature requests log

Things asked for that the product does not have yet, in the owner's words, with where he was
and what happened. The in-app Assistant owns this list once it exists (Admin → Requests); until
then it is kept here by hand, in the same turn the gap is found.

| # | Asked (verbatim) | When | Where | Status |
|---|---|---|---|---|
| 1 | "Make sure there's an AI assistant I can use to switch screens and get where I need … a chat box separate of terminal/board open in every screen, like an app manager controlling everything and logging feature requests as we find things I ask for we don't have" | 2026-09-18 | UI review | Designed — review §Surface 4; plan v0.1 (CommandRegistry) |
| 2 | "everything rebuilt for Mac/iOS" → "we need a full iOS app same as Termius" | 2026-09-17/18 | planning | Decided — full iOS parity; plan rewritten: embedded libssh2 core on both platforms, app is its own agent, tmux persistence (the Termius method) |
| 3 | "every tool … should use my color" → "Colors should fit color scheme of logo … Meant plural … I do like that pink though" | 2026-09-17/18 | planning | Decided — one logo primary per tool; the site's pink becomes the Assistant's colour, used nowhere else |
| 4 | "without protections … always have GitHub option to restore … Not as a toggle but as a back up" | 2026-09-18 | planning | Decided — no gates; commit before/after every run, push to GitHub, one-step restore to previous version |
| 5 | "GF droplet would remain as client facing droplet with all the GF branded web tools. This Multi platform app would utilize cloud based terminal so iOS works with it" | 2026-09-18 | planning | Decided — separate LodiStudios session droplet; GF droplet stays client-facing; sessions persist in tmux in the cloud, devices attach |
| 6 | "Come up with a dozen other features … visuals, drag and drop edits, in preview text editing, maybe highlight text … make write ups as easy as possible to mark attach a note that the AI looks for and reads" | 2026-09-18 | UI review | Designed — `docs/webpro-markup.md`: Marks + Brief mechanism, 14 features, build order |
