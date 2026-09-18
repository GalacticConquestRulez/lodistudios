# LodiStudios — UI review (personal daily driver)

Reviewed against `/root/LodiStudios-plan.md`, the logo, and lodistudios.com as it renders today.
Written from a week of watching how the owner actually works: phone and Mac, many parallel
runs, credit-conscious, corrections that want capturing, third-party consoles with "whose turn"
steps, secrets pasted into chat, sites whose DNS quietly pointed elsewhere.

## Verdict
The plan is an architecture with a palette. It does not yet have a UI. What it needs is not
five tools' worth of screens — it is **four shared surfaces** that every tool lives inside:
a live **Board**, a native **Run view**, a **⌘K command palette**, and the **Assistant** that can drive all of them. Get those right and the
five tools are mostly content inside them.

## Keep (these are right)
- One app, not five that ship together. Same chrome, same sidebar; only the working area and the accent change.
- Black and white carry the interface; one primary per tool does the pointing.
- Terminal scrollback is never branded; only its chrome is.
- `PaneOutputSink` / `PaneWriter` in week one. They are what make the Run view possible.
- Sessions live on the droplet; the Mac is the powerful half. Mac App Store ruled out, recorded.

## Gaps, ranked

### 1. No home screen → make it a live Board, not a launcher
Five big tool tiles is a launcher. A daily driver opens on *what is happening now*:
running sessions and agents (with the last line of output), deploys in flight, timers and
their last result, sites with a health line, and the human to-do queue.
This week alone the Board would have shown: 21 unpushed commits on greenflash-src, a client
domain resolving to a foreign IP serving an old build, a droplet 1.9 GB into swap. Nothing shows
those today. The Board's data is nearly free — `git status`, `systemctl list-timers`,
`certbot certificates`, `dig`, `free` over the SSH connection v0.1 already opens.

### 2. No run view → the Claude Code Run view is the killer feature, not the terminal
Most of the day is watching Claude work inside a tmux TUI. Render it natively: a timeline of
tool calls (collapsed by default), diffs inline, a cost ticker and budget bar, the model badge,
Stop and Send-message controls, subagents nested under their parent. Raw terminal one tab over.
**It does not need tmux control mode.** Claude Code writes JSONL transcripts under
`~/.claude/projects/`; tail that file over the same SSH connection and the Run view is a
parser plus a list. That pulls it from v0.3 into v0.1 as read-only.

### 3. No navigation model → ⌘K is the primary navigation
One power user, dozens of hosts, sites and sessions: typing "jbn deploy", "ssh droplet",
"reviews log" beats clicking through tools. Every action in the app registers as a command;
fuzzy match; recents first. Plus a menu-bar status item: count of running runs, click to attach.

### 4. The colour system has a semantic collision
Red is Infrastructure Pro's accent *and* the colour of an error. Green is LodiTerminal *and*
"ok". In a tool whose job includes monitoring, a red glow must never mean "you are in Infra Pro".
Rule: **tool accents live only in chrome** (sidebar item, tab underline, window eyebrow);
**status lives only in content**, as shape + word first (● ok, ▲ warn, ✕ fail) with a separate,
slightly desaturated status trio that is not the brand primaries. Dark only — do not build a
light mode for an app with one user.

### 5. Site cards must show operational truth
In WebPro, each site: live-tree git status (uncommitted changes?), ahead/behind GitHub, last
deploy, last backup, cert expiry, DNS → this box?, HTTP status. This is Admin data surfacing
where the decision gets made. And the site's Playbook (`CLAUDE.md`) editor sits on the card,
not three menus down — captured corrections are the compounding asset.

### 6. Human to-do inbox from day one, not Phase 4
A cross-tool "waiting on you" queue: each item says who, where, with a link, and ticks itself
when detected (the reviews-admin pattern). This week's queue: get a client's profile URL, send a
tester invite, email GRAR, rotate an app secret, fix a contact-email typo. Today those live in
chat scrollback.

### 7. Secrets never go through chat
A drop-box: paste a secret → written straight to the host's env file over SFTP → the UI shows
presence and age only. Keychain for anything local. An app secret went through the chat
transcript today because there was nowhere else to put it.

### 8. Notifications
Run finished / failed, deploy done, timer failed, cert expiring inside 14 days, subagent done —
macOS notifications with actions (Attach, Open diff). Terminal bell → notification. This is also
where the phone companion earns its keep later: notifications, approve/deny, read a transcript.
Not a terminal.

### 9. Screenshot-to-Claude
One key captures a region and attaches it to the current run. The owner photographed his own
laptop with his phone today to show a dashboard to the AI. The app should make that one keystroke.

### 10. Model and cost as controls, not memory
Model picker per run: Opus default, Sonnet/Haiku one click, Fable behind a confirmation.
Per-run and per-day cost in the status bar; budget caps. The standing policy becomes a control.

## Surface 4 — the Assistant (app manager)
Asked for on 2026-09-18, in the owner's words: *"an AI assistant I can use to switch screens and
get where I need … access any toggle for me from a chat box separate of terminal/board open in
every screen, like an app manager controlling everything and logging feature requests as we find
things I ask for we don't have."*

**What it is.** A chat panel present on every screen — docked right, or a drawer — with a global
shortcut. Separate from terminal panes and from the Board. Never modal; never steals focus from a
terminal.

**What it does.** Navigate anywhere ("open jbn's reviews log"); run any control ("turn the
reviews timer off", "attach to droplet"); read what is on screen and explain it ("why is
Hewanorra red?"); capture a standing rule ("from now on always…" → Playbook); and log a feature
request when it cannot do what was asked.

**The rule that makes "any toggle" true rather than hopeful: everything is a Command.**
Every toggle, button, menu item and shortcut in the app is a registered `Command` — id, title,
tool, description, parameter schema, `destructive` flag, availability given current state, and
the code that runs it. Views invoke commands; nothing in a view has a bare action of its own.
The assistant's tool list is generated from the registry, so every feature is controllable the
day it is added, without anyone remembering to wire it. The same registry powers ⌘K, the menus,
keyboard shortcuts, a `lodi` CLI / URL scheme, and the audit log. Build it in week one, beside
`PaneOutputSink`: retrofitting it touches every view.

**Confirmation.** Commands flagged destructive (deploy, apply, delete, restart) get one inline
confirmation showing the exact command and arguments; everything else runs immediately.

**Feature requests.** When a request matches no command, or a command refuses, the assistant
logs it — the ask verbatim, the tool and screen, the selection, the time — to **Requests**
(Admin → Requests; badge on the Board). "Log this" works by hand too. Requests export as a brief
for an Opus build, so the list is a spec in waiting, not a wish list.

**Context.** The assistant sees the current tool and screen, the selection, a compact Board
summary, and — on request — the last N lines of the focused pane as stripped text. Never whole
scrollbacks.

**Models.** The standing policy applies: Opus by default, Sonnet if chosen, Haiku for cheap
intent-to-command routing, Fable only by explicit choice.

**Phone.** The iPhone build is a full LodiStudios, not a companion (owner's decision, 2026-09-18):
same embedded SSH core, same command registry, same Assistant. The Assistant is still the surface
that makes the phone useful first — it drives everything by text before the touch chrome is refined.

**Build order.** Command registry: v0.1, week one. Assistant panel with navigate + invoke +
log requests: v0.1. Read-screen and rule capture: v0.2.

## Platform power — what the developer account unlocks, by priority (2026-09-18)
The lever is the command registry: every command becomes an App Intent (Siri, Shortcuts, Action
Button, Spotlight), a widget action, a notification action, a deep link, and a `lodi` CLI verb.

**First (cheap, changes how the phone feels):** push relay on the session droplet fed by Claude
Code hooks and timers → APNs; Live Activities + Dynamic Island for runs and deploys; Board
widgets; Face ID gates on destructive commands and secret reveal, per-device Secure Enclave keys
registered on the droplet by the app, never synced; Share extension (screenshot/file → site or
run); CloudKit private sync of hosts, snippets, playbooks, requests, Board snapshot; universal
app so iPad gets the Mac layout with Stage Manager and external display.

**Second:** FileProvider (SFTP in Files.app and Finder); on-device Foundation Models for the
Assistant's intent routing (free, offline; Claude only for real work); Handoff between devices;
background URLSession for transfers and silent-push Board refresh; Mac menu-bar extra with a
global Assistant hotkey; ScreenCaptureKit region → Claude.

**Later, desktop-only:** local Claude Code runs for AppPro with the same Run view; Simulator
build-and-screenshot loop; Virtualization framework VMs to rehearse Infra Pro changes; Xcode
Cloud for the app's own CI; Apple Watch complication + approve/deny.

**Constraints:** iOS ends background execution in ~30 s — everything is designed around cloud
sessions, push instead of polling, background transfers, and an opt-in location keep-alive. Each
extension is its own target: add one per version; only push in v0.1.

## Per-tool notes
**LodiTerminal v0.1** — host list with groups (droplet / client servers); one-key attach;
reconnect banner that says why ("tmux server restarted — previous output not available");
Cmd-F; a snippets drawer (`deploy jbn`, `cc`, `gd-dns`); select text → "Ask Claude about this"
(the stripped-text pane feeds it). Later: splits, port-forward toggles, a key manager that
renders destination constraints as a UI, SFTP drop targets on host and site cards.

**WebPro** — site list with the status line above; run Claude on the live tree with a mandatory
pre-run commit and a one-idea-per-commit message box; preview ↔ live switch; before/after
screenshot diff; deploy log; **client report generator**: commit range → co-branded PDF (done
by hand three times this week).

**Infrastructure Pro** — read-only scan → report; diff against the last scan; approve then apply;
per-host rules in the Playbook.

**LodiAdmin** — DNS (gd-dns) with a zone list; certificates table; timers and services with
last result; disk / swap / memory; backups; repos ahead/behind; the audit log. Most of it is a
command's output rendered well, and it is what the Board reads from — build the data layer once.

**AppPro** — the map-as-plan idea stands; nothing to add until the three surfaces exist.

## Identity — settled
lodistudios.com and the LodiStudios app are **separate entities** (owner's decision). The site is
a creative studio — AI music, animation, aerial, aquatic — in pink→purple, for its own audience.
The app is a developer homebase in four primaries on black, for one user. Neither is brought to
the other: the app follows the logo, and the eye is a usable motif (app icon, busy state,
Infrastructure Pro "watching"). Aside, unrelated: the site's four service-card icons render as
empty boxes — a missing icon font, quick fix.

## The shell
```
┌──────────┬──────────────────────────────────────────┬───────────────┐
│ ● Board  │  tabs:  [jbn: reviews run] [droplet] [+]  │  inspector    │
│ ● Term   │                                          │  host / run   │
│ ● WebPro │   main working area — the tool's content │  cost, model  │
│ ● Infra  │   (Board, terminal, run timeline, site)  │  files, diff  │
│ ● Admin  │                                          │               │
│ ● AppPro │                                          │               │
│──────────│                                          │               │
│ to-do 3  │                                          │               │
├──────────┴──────────────────────────────────────────┴───────────────┤
│ $4.12 today · 2 runs · droplet ● · client1 ●            ⌘K to jump  │
└─────────────────────────────────────────────────────────────────────┘
```
Sidebar dots carry the tool accent; nothing else does. SF Mono for content, SF Pro for chrome,
high density, every action has a shortcut. Single window; terminals can detach.

## Build-order change
v0.1 = terminal + Board (read-only) + ⌘K + the command registry and Assistant panel. The Board's data is nearly free and it is what makes
the app worth opening every morning. Run view (read-only, from the JSONL transcript) in v0.2.
Control mode stays v0.3, and stays optional.

## Coverage against what was asked (checked 2026-09-18)
| Asked | Where | Status |
|---|---|---|
| Perpetual cloud SSH, replace Termius | Plan Phase 1 | v0.1 |
| SFTP | Plan v0.2 | one week after v0.1 |
| Website builder on the live tree, no clones, no protections | Plan Phase 3 | yes; the pre-run git commit is an undo, not a gate — make it a toggle if the owner counts it as protection |
| App builder: web + iOS + Android from day one | Plan Phase 4 | yes |
| 20–30 AI phases + human to-do list | Plan Phase 4; review pulls to-do to day one | yes |
| Infrastructure Pro over SSH, plan → apply | Plan Phase 2 | yes |
| LodiAdmin: admin, security, analytics, droplets, DNS | Plan Phase 5 | yes, except analytics has no data source — decide what to measure first |
| Homebase, one app; SwiftUI; Apple Silicon; single user; separate from the web studio | Plan | yes |
| Branding from the logo, "every tool should use my color" | Plan design system | read as one primary per tool — CONFIRM whether one colour was meant |
| Mac/iOS | Plan defers iOS | NOT as asked — review proposes a phone companion first; confirm companion vs parity |
