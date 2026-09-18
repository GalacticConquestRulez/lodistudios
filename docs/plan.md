# LodiStudios

## Context

Green Flash Studio can build and ship websites. Three phases of it are in
production: a passkey-authenticated web app that drives Claude Code runs against
a project, a brief builder that turns a client questionnaire into a creative
brief, and custom-domain attachment with a root helper that writes nginx vhosts
and runs certbot. It works, and it is limited to websites.

The ask is to stop being a website company. Five products under one roof:

- **LodiTerminal** — perpetual cloud SSH/SFTP, replacing Termius.
- **WebPro** — the website builder, working directly on live site trees rather
  than sandboxed clones.
- **AppPro** — an application builder targeting web, iOS and Android from one
  visual, adaptive environment, where a large concept is planned once and then
  decomposed into 20–30 AI-executable phases plus a human to-do list for the
  parts a model cannot do.
- **LodiAdmin** — admin, security and analytics, plus droplets, DNS and more.
- **Infrastructure Pro** — SSH into a client's servers, run a full
  infrastructure analysis, and let Claude plan and apply improvements *over the
  SSH connection*, rather than pulling their files onto our box.

The intended outcome is a homebase the owner works from every day, which grows
to cover the whole surface of the business rather than one slice of it.

## The starting position, established by exploration rather than assumed

**About 40% of a platform already exists** in `/srv/sitebuilder/bot`. Its
services layer was written under a rule that has actually been kept — *"Nothing
in this package may import from `tg/`, or from the web app"* — so these are
product-agnostic today and reusable by anything:

| Reusable now | Path |
|---|---|
| The run engine (spawns Claude Code, streams stream-json, kills the process group) | `sitebuilder/runner.py` |
| Run manager, refusal/crash handling, stop semantics | `sitebuilder/services/runs.py` |
| Cross-process concurrency lock (one atomic SQL statement; PID + cmdline liveness) | `sitebuilder/registry.py:482-645` |
| Append-only run transcripts | `sitebuilder/services/runlog.py` |
| Budget caps and cost bands | `services/budget.py`, `services/costs.py` |
| Standing rules injected into every prompt | `services/playbook.py` |
| Resumable event stream with `Last-Event-ID` | `sitebuilder/web/sse.py` |
| Passkey auth, CSRF, security headers, audit | `web/auth.py`, `web/csrf.py`, `web/middleware.py`, `web/audit.py` |
| **Privilege separation: unprivileged app queues intent, root re-derives every fact** | `services/domains.py` + `deploy/studio-domaind` |

**Server-side session persistence is already solved.** `/usr/local/bin/cc-sessions`
snapshots live tmux sessions every five minutes and restores them after reboot;
`/usr/local/bin/cc` attaches or creates one. The hard half of "perpetual" exists.

**Genuinely absent:** any SSH or SFTP code, any DigitalOcean API access or
credential, any second human in the web app's identity model, any analytics data
source, and any mobile toolchain.

## The shape

Two decisions taken by the owner make this much cheaper than it first looked.

**LodiStudios is a native macOS app, not a web app.** SwiftUI, Apple Silicon,
one user. Green Flash Studio stays where it is, at its own domain, as the
website product. So LodiStudios is not a refactor of the studio's registry,
routes or project model — it is a new thing beside it, and the painful
generalisations (polymorphic `projects` table, per-product prompt families,
per-product tool policy) are *deferred until a product actually needs them*.

**Completely separate from the web studio, and it must not interfere with it.**
Not a second front end over the same backend, not a skin, not a client of it.
LodiStudios is its own product with its own branding, its own UI and its own
data, and it keeps working if `studio.greenflashusa.com` is down — and, more
importantly, the reverse: nothing in LodiStudios may change the behaviour of the
Green Flash web platform, which **exists as-is and stays as-is**. It serves 17
client sites and a paying client's held refresh; it is not to be refactored in
service of this.

**Everything is rebuilt natively for Apple platforms.** No web views, no ported
HTML. Where LodiStudios needs a capability the web studio already has, it gets a
native implementation rather than a dependency.

**macOS and iOS from the start, on one transport.** The owner's decision
(2026-09-18): *"we need a full iOS app same as Termius."* Termius's method,
verified against their own support material and the libraries' documentation,
is an embedded SSH library rather than a spawned `ssh` — iOS has no subprocess
execution, so that was never available there. Using the same embedded core on
the Mac gives one codebase, native channel multiplexing instead of
ControlMaster, and a transport that behaves identically on both devices. The
"let OpenSSH do the hard parts" design from the first draft is withdrawn; what
OpenSSH gave for free is listed below with what replaces it.

**One user: the owner.** No multi-tenancy, no client logins, no review links, no
roles. This removes what the exploration identified as the single largest
refactor in the whole idea — reconciling the Telegram identity model with the
studio's single-passkey owner table — because LodiStudios simply never needs it.
Say so explicitly in the code, or someone will build it in anyway.

That separation is what makes native WebPro simple rather than complicated. It
does not call the studio's API; it does what every other tool in LodiStudios
does — **runs Claude Code on the Mac, reaching live site trees over the SSH and
SFTP transport that LodiTerminal already provides.** No new API surface, no
machine-facing auth, no scoped token, no second consumer of the studio's
services layer to keep in step. It also lands exactly where the owner asked
WebPro to be: on the real tree, not a clone.

This is the strongest argument for the build order below. LodiTerminal is not
just first because it is useful first — its transport is the substrate every
other tool in the app stands on.

**The Mac is the powerful half; the droplet is only always-on.** The M1 Max
builds iOS, Android and web — none of which this 2-vCPU Linux droplet can do,
and iOS it could never do at any size. So:

```
  M1 Max MacBook Pro                     Droplet (142.93.198.162)
  ─────────────────────                  ────────────────────────
  LodiStudios.app (SwiftUI)   ──SSH──▶   sshd + tmux  (perpetual sessions)
  SSH keys in Keychain        ──agent──▶ forwarded only at connect time
  Xcode / Gradle / Metro                 nginx + 17 client sites
  Claude Code, driving work              Green Flash Studio (WebPro)
```

**Keys never land on the droplet.** Agent forwarding authenticates the onward
hop at connection time; the session survives the agent going away, so closing
the laptop does not kill it. A droplet compromise does not become a compromise
of every client's infrastructure — which matters, because that box also serves
17 public websites.

The accepted consequence: **starting a new session requires the Mac awake**, so
nothing runs unattended. That rules out scheduled overnight infrastructure scans
until a per-host, droplet-held key is added — a decision deliberately deferred
to Phase 2, when it is known whether clients would pay for them.

## Order of work, and why

The owner chose LodiTerminal first, and it is the right choice for reasons worth
recording: he uses it daily so he will feel every flaw immediately; it has no AI
dependency so nothing blocks it; and it forces the host inventory, the
credential handling and the session plumbing into existence — which
Infrastructure Pro then reuses almost entirely.

1. **Phase 0 — prerequisites.** Blocking, and small.
2. **Phase 1 — LodiTerminal v1.** Replace Termius for one user.
3. **Phase 2 — Infrastructure Pro.** Claude over the SSH session that Phase 1
   already knows how to open. This is the cheapest large win on the list.
4. **Phase 3 — WebPro on live trees.** Native, over LodiTerminal's transport.
5. **Phase 4 — AppPro.** The largest, with real external dependencies.
6. **Phase 5 — LodiAdmin.** Deliberately last: its droplet half needs a
   DigitalOcean credential that does not exist, and its analytics half needs a
   data source that does not exist.

## One design system, all five tools

The identity comes from the **logo**: four saturated primaries on black, with a
cartoon eye in the O. Sampled from the mark itself:

| Token | Value | In the logo |
|---|---|---|
| `lodiBlue` | **`#026BFD`** | the L |
| `lodiYellow` | **`#FED606`** | the O |
| `lodiRed` | **`#FC1E26`** | the D |
| `lodiGreen` | **`#12DE3F`** | the I |
| `lodiInk` | **`#000000`** | the ground — 41% of the mark |
| `lodiPaper` | **`#FFFFFF`** | STUDIOS |
| `lodiPink` | **`#FF4FA0`** | not in the logo — the site's pink, kept for one job (below) |

**Settled (2026-09-18):** the site and the app are separate entities; the app
follows the logo and the site keeps its gradient. The owner likes the site's
pink, though, and it has exactly one job in the app: **it is the Assistant's
colour.** The Assistant is the only surface that crosses every tool, so it
cannot borrow a tool's accent — it needs its own, and pink is off the logo's
palette precisely so it never reads as a sixth tool. Rule: pink appears only
inside the Assistant panel (its eye's focus ring, its send control, its
selected turn), never in a tool's working area, never in the sidebar. The one
pairing to check in a mockup is pink beside Infrastructure Pro's red; they are
far apart on screen, which is the mitigation.

### Using four primaries without it looking like a toy

This palette is genuinely hard, and pretending otherwise is how it goes wrong.
Four equally-weighted saturated hues on black is a *logo* strategy; applied
evenly across a working tool it reads as a children's app and becomes
unreadable, because none of the four can be "the important one".

The rule that makes it work: **black and white do the work, the primaries do the
pointing.**

- Black is the ground and white is nearly all the text — exactly the ratio in
  the mark itself.
- A primary appears where something is *this tool's* or *needs you*. Never as a
  large fill, never two competing in one view.
- **One primary per tool**, so colour is wayfinding rather than decoration —
  you know which tool you are in peripherally, before reading a word.
  LodiTerminal green, WebPro blue, AppPro yellow, Infrastructure Pro red, and
  LodiAdmin white on black. Then every tool "uses the colour" and the full
  palette appears across the product, without four of them shouting in one
  window.
- The **eye** is the strongest asset in the mark and should be used, not just
  placed: the app icon, the busy/attention state, and — fittingly — Infrastructure
  Pro watching a host.

### Two consequences, both easy to get wrong

- **The five tools are one app, not five that ship together.** Same chrome, same
  sidebar, same command surface. What changes between them is the working area
  and the accent, not the furniture.
- **The terminal is the exception that proves it.** Terminal content is ANSI —
  sixteen colours the *remote program* chooses, not ours. Brand the chrome,
  tabs, status bar and cursor; leave the scrollback alone. A terminal theme that
  fights `ls --color` is a terminal nobody uses. The `lodiGreen` accent belongs
  on LodiTerminal's tab bar, not inside the pane.

In SwiftUI these live in one `LodiTheme` in `LodiKit` with semantic names
(`Color.lodiAccent` resolving per tool; never a hex literal in a view), so every
tool and every future target reads the same values.

---

## Phase 0 — prerequisites

Two are broken now and will break builds before any feature does.

- **`/tmp` is a 2 GB RAM-backed tmpfs at 90% full** (1.5 GB of it
  `/tmp/claude-0`, 177 MB stale pytest trees, a dozen stale `.html` dumps). npm,
  Next.js and certbot all write there. Clear it, and add a periodic sweep.
- **The box is 1.9 GB into swap at idle** with 3.8 GB of RAM. Nothing new of
  consequence fits until it is resized. The owner's answer is "here for now,
  move over soon" — so treat this as a known ceiling, not a surprise.
- **Delete `/root/{Lodi,Angel,Josh,Livius}.json`** — plaintext refresh tokens
  from abandoned automation. A live credential exposure with no upside.
- **Reclaim the obvious waste**: `/root/lodi-upload` and
  `/root/lodistudios-upload` are two ~99 MB clones of one repo; 35 identical
  `greenflash.bak.*` files litter `/etc/nginx/sites-available/`; `/root/shot`
  holds 97 MB of one-off screenshots. Roughly 300 MB, and it makes the tree
  legible.

---

## Phase 1 — LodiTerminal v1

**The goal is narrow and testable: replace Termius for one user.** Not a
product for sale, not multi-user, not cross-platform.

### Architecture: tmux over SSH, and no new droplet code

The leanest correct v1 writes **nothing** on the server. Perpetual sessions are
`ssh` to the droplet plus `tmux attach -t <name>`, and that already works today —
`cc-sessions` restores tmux sessions across reboots, `cc` creates and attaches
them. A custom session broker buys reconnection from a device that is not the
Mac, which is not v1's problem.

What that means in practice:

| Event | What happens |
|---|---|
| Laptop sleeps / lid closes | The SSH connection drops; the tmux session and everything running in it survive on the droplet. Reattach on wake. |
| Wifi → hotspot | The TCP connection dies. The app reconnects and reattaches; scrollback comes from tmux, not from the app's memory. |
| Droplet reboots | `cc-sessions` restores the session list from `/var/lib/cc-sessions/sessions.tsv`. Processes inside are gone — that is honest and should be shown, not hidden. |
| A session left a week | Reattaches with its scrollback. The onward SSH hop it opened is still authenticated, because auth happened once at connect time. |

The onward hop to a *client's* server is opened **from inside the tmux session**
using the forwarded agent. So the chain is: Mac → droplet (agent forwarded) →
client server. Key material never rests on the droplet, and the session persists
after the agent is gone.

### Libraries: an embedded SSH core — the Termius method

Verified at source level, and it settles what *not* to use: **`apple/swift-nio-ssh`
cannot do agent forwarding at all** — `SSHChannelType` is a closed enum with no
`auth-agent@openssh.com`, `ChildChannelUserEvents` cannot even request it, and
`UserAuthenticationMethod.privateKey` demands in-memory key material, which
rules out Secure Enclave keys forever. Citadel inherits all three. Both SwiftSH
forks last saw code in 2021.

What the shipping mobile terminals actually use:

- **Termius** — `libssh2` (they patch it themselves; they shipped a fix for
  CVE-2026-55200 in 2026), plus a closed-source Mosh implementation of their own.
- **Blink Shell** — `libssh` with an in-app agent, Secure Enclave keys, and
  the GPL Mosh client compiled in. Open source under GPLv3: study it, do not copy it.

**Decision: `libssh2`, built as an xcframework for iOS and macOS.** BSD-licensed,
so nothing changes if the app is ever distributed. It supplies, verified in its
documentation and shipped example (`ssh2_agent_forwarding.c`):

- **Agent forwarding** — `libssh2_channel_request_auth_agent()` (in every release
  after 1.9.0). The library itself accepts the `auth-agent@openssh.com` channels
  the remote side opens and proxies them to the local agent; the application
  never touches the agent protocol on the wire. One known sharp edge: issue #535,
  a blocking read after the agent request — the example runs the session
  non-blocking with `libssh2_session_block_directions()`, and so must we.
- **Custom signing** — `libssh2_userauth_publickey()` takes a sign callback, so a
  private key can live in the Keychain or the Secure Enclave and never be
  exported; the callback calls `SecKeyCreateSignature`. That is the Secure
  Enclave story, on both platforms, without a community gist.
- **SFTP** — `libssh2_sftp_*`, complete. The hand-written v3 codec in the first
  draft is deleted.
- **Direct-tcpip channels** — jump hosts and port forwards over the one connection.

What the app must build itself, once, shared by both platforms:

- **An in-app SSH agent.** A Unix-domain socket inside the app's own container
  (allowed on iOS and on a sandboxed Mac), speaking the OpenSSH agent protocol,
  answering with Keychain- or Secure-Enclave-backed keys. libssh2 uses it for
  local authentication and proxies forwarded requests to it. *The app is the
  agent* — which is what makes the security control below possible.
- **known_hosts** — a small store with the usual first-connect prompt and
  changed-key refusal.
- **Reconnect** — see the iOS notes below; the sessions themselves live in tmux
  on the droplet, exactly as before, so a dropped TCP connection costs nothing
  but the reattach.

- **Terminal rendering: SwiftTerm** (MIT, active; ships in Secure ShellFish and
  CodeEdit). It has both a UIKit `TerminalView` for iOS and an AppKit one for
  macOS, so the emulator is shared too. Drive it via the `HeadlessTerminal`
  pattern; there is no local process.
- **Mosh: optional, v0.4.** Termius wrote their own; Blink compiles the GPL
  client. For a personal app that is never distributed the GPL costs nothing,
  so Blink's route is open. It is not needed for v1 because tmux already
  survives the disconnect; it buys instant roaming, not persistence.
- **libghostty: not yet.** Still alpha, C API unpublished. Keep a
  `TerminalSurface` protocol in front of SwiftTerm and revisit in a year.

### iOS, honestly

iOS ends background execution in roughly 20–30 seconds (Termius's own support
page says so; older versions allowed two to three minutes). Every serious
client has the same three answers and so will this one:

1. **Sessions live in tmux on the droplet**, so backgrounding costs only the
   reattach. This is the real answer and it is already built.
2. **Reconnect on foreground, automatically**, with the scrollback restored
   from tmux — never from the app's memory.
3. **An opt-in location keep-alive.** Both Termius and Blink keep the socket
   open in the background by enabling location tracking, because iOS keeps an
   app alive for that. Offer it as a switch; do not turn it on by default.

Installing on the owner's own iPhone needs the $99 Apple Developer account and
either Xcode or TestFlight; a free account's builds expire after seven days.
That account is already a Phase 4 human to-do item — it moves to Phase 1.

### The security control that matters most

In the first draft this was `ssh-add -h` — OpenSSH's destination constraints,
binding a forwarded key to specific hop paths. With the app acting as its own
agent, **the app enforces the same constraints itself**: OpenSSH on the droplet
still sends `session-bind@openssh.com` to the forwarded agent for every onward
hop, and our agent refuses to sign for any destination not in the host
inventory. Same guarantee, generated from the same inventory:

```
droplet                    -> may use key
droplet > client1.example  -> may use key
anything else              -> refused, logged, shown in the Board
```

**If the droplet is ever compromised, the attacker cannot use the forwarded
agent to reach anything outside the inventory.** Given the agent is being
forwarded into a box that serves 17 client websites, this is not optional —
and because the agent is ours, every refusal is visible in the app rather than
silent in a syslog.

### Where the sessions live: a droplet of their own

Owner's constraint (2026-09-18): the Green Flash droplet *stays client-facing* —
the 17 sites and the Green Flash-branded web tools — and LodiStudios uses a
**cloud-based terminal**, which is what makes the iPhone a full client: the
sessions persist in the cloud, the phone only attaches.

So LodiStudios gets a **session droplet of its own**: tmux sessions, the
Claude Code runs the app drives (from the phone there is no Mac to run them
on, so they run here), and the onward SSH hops to the Green Flash droplet and
to client servers. The Mac keeps the jobs only a Mac can do — Xcode, Gradle,
the app itself.

This also dissolves the plan's largest security worry. The forwarded agent
now lands on a private box that serves nothing public, and the Green Flash
droplet becomes just another host in the inventory — reached through the
in-app agent's destination constraints like any client server, never holding
a key. Sizing is in the "droplet ceiling" risk below and in
`/root/LodiStudios-ui-review.md`.

### The only droplet change v1 needs — four lines, no new services

When the Mac disconnects, the forwarded agent socket is deleted and the tmux
session's `SSH_AUTH_SOCK` points at a dead path, so `git push` from inside tmux
fails after reconnecting. There is currently no `/root/.ssh/rc`. Add one that
symlinks the socket to a stable path, and set `SSH_AUTH_SOCK` to that path in
`/root/.tmux.conf`.

### Build order — smallest useful thing first

- **v0.1, ~2 weeks — "I can stop opening Termius."** Host inventory; an
  `ssh_config` rendered from it (golden-file tested, and the single place every
  connection option is decided); ControlMaster lifecycle; one terminal tab per
  host via **plain attach** (`ssh -t host 'tmux new -A -s <name>'`); the in-app agent; sleep/wake and network-change reconnect. That is genuinely
  enough to switch, because tmux and OpenSSH already solve the hard parts.
- **v0.2, +1 week** — SFTP browsing, transfers, drag and drop, from libssh2's
  own SFTP. The iOS build reaches v0.1 parity here: same core, same emulator,
  touch chrome.
- **v0.3, +2 weeks** — tmux **control mode** (`tmux -CC`), native tabs and
  splits, `capture-pane` history replay, Cmd-F. This is the version that looks
  like a Mac app.
- **v0.4, +1 week** — remote editing with atomic save-back and conflict
  detection; destination constraints in the in-app agent; Secure Enclave keys
  through the sign callback; droplet-reboot detection; port forwarding; the
  iOS location keep-alive switch; Mosh if wanted.

Ship v0.1 on plain attach *specifically so* a slip in control mode costs
nothing operationally — control mode is the schedule risk here, the place
iTerm2 spent years, and plain attach with nicer chrome is a legitimate
permanent answer if it fights back.

### Three things to get right in week one, because retrofitting them is expensive

Infrastructure Pro is Claude Code running *on the Mac*, reaching a client host
over the session Phase 1 already knows how to open. In control mode tmux hands
over each pane's output already demultiplexed and addressed (`%output %42 …`),
so:

- **`PaneOutputSink`** — `TmuxControlClient` broadcasts to a fan of sinks rather
  than calling the terminal view directly. The terminal is then *one* sink; an
  AI observer is another; a transcript recorder is another. Adding an agent to a
  live session becomes zero changes to the transport. Wire output straight into
  the view — the obvious thing to do at 11pm in week two — and retrofitting this
  later touches everything.
- **`PaneWriter`** — keyboard input and an agent's `send-keys` go through one
  door, with a policy object in front of it (rate limit, confirm-before-execute,
  read-only). Put it in while there is exactly one caller and the policy is
  trivially "allow".

- **`CommandRegistry`** — every toggle, button, menu item and shortcut in the app
  is a registered `Command` (id, title, tool, description, parameter schema,
  `destructive` flag, availability, run). Views invoke commands and have no bare
  actions of their own. This is what makes the owner's **Assistant** — a chat
  panel on every screen that can switch screens, operate any control, and log a
  feature request when it cannot — true by construction: its tool list is
  generated from the registry, so each new feature is controllable the day it
  lands. The same registry powers ⌘K, menus, shortcuts, a `lodi` CLI and the
  audit log. See `/root/LodiStudios-ui-review.md`, Surface 4. Put it in while
  there are ten commands, not four hundred.

Also cheap now and invaluable later: a second *headless* SwiftTerm per pane
whose only job is to strip escape sequences into clean text. An LLM should never
be shown raw VT100.

### Platform power, by priority

Full list in `/root/LodiStudios-ui-review.md` ("Platform power"). The order of
work: **v0.1** — push relay on the session droplet (Claude Code hooks and
timers → APNs) and the command registry exposed as App Intents. **v0.2** —
Live Activities, Board widgets, Face ID gates, per-device Secure Enclave keys,
Share extension, CloudKit sync. **v0.3** — FileProvider in Files and Finder,
on-device Foundation Models for Assistant routing, Handoff, background
transfers. **Later** — Simulator loop, Virtualization VMs, Xcode Cloud, Watch.
One extension target per version; none in v0.1 but push.

### Honest notes

- **Droplet reboot does not restore processes.** `cc-sessions` recreates the
  session name and working directory; it does not restore scrollback or running
  commands. The app must say so — record the tmux server PID and, when it
  changes, show "tmux server restarted, previous output not available" rather
  than an empty pane that reads as data loss.
- **A week-old session's history can be 20–100 MB per pane** at the droplet's
  current `history-limit 200000`. Replay the last 5,000 lines and fetch older
  windows lazily. Skip replay entirely when the pane is on the alternate screen
  (vim, htop, a Claude TUI) — the history is not there and replay produces
  garbage.
- **Touch ID on every signature composes badly with agent forwarding**: each
  onward hop prompts, possibly mid-keystroke. Decide that policy deliberately.
- **Secure Enclave keys go through libssh2's sign callback**, not a shell
  trick: generate a `kSecAttrTokenIDSecureEnclave` EC key, sign with
  `SecKeyCreateSignature`, present it as `ecdsa-sha2-nistp256`. Prove the round
  trip against the droplet in week one, before any UI depends on it; the
  fallback is an ordinary Keychain-held ed25519 key, which loses only the
  cannot-be-extracted property.

---

## Phase 2 — Infrastructure Pro

The insight that makes this cheap: **the analysis runs on the Mac, not on the
droplet.** Claude Code already runs locally; once LodiTerminal can open an
authenticated session to a client server, an infrastructure run is a Claude Code
run whose tools reach that host over SSH. Nothing is copied onto our box, which
is exactly what the owner asked for.

What it needs beyond Phase 1:
- A **read-only first pass** by default: inventory services, ports, certs, disk,
  updates, backups, exposed surface — and write a report, changing nothing.
- A **plan → approve → apply** gate, mirroring the studio's existing shape
  (`services/projects.py` phases, `web/flows.py:_start`). Applying changes to a
  client's production server without an approval step is not a feature.
- **Per-host standing rules**, reusing the playbook mechanism
  (`services/playbook.py`) — "this host's nginx is managed by Plesk, never edit
  vhosts by hand" is exactly what that table is for.
- A snapshot equivalent: before any change, record what it was, so the report
  can say what to put back.

The Hewanorra case from this week is the worked example: a client's hostname
resolved to a different server serving an old build, everything looked fine, and
nobody noticed. That is precisely what a scheduled infrastructure pass catches.

---

## Phase 3 — WebPro on live trees

A LodiStudios tool, built on LodiTerminal's transport — not a front end over the
web studio, which keeps running untouched for clients.

The shape: pick a site, and WebPro opens its **live tree** on the droplet over
SFTP, runs Claude Code on the Mac against it, and shows the result. No clone, no
preview gate, no approval step, which is what was asked for.

**Keep snapshot and rollback.** A git commit before every run, so undoing one is
free. The web studio proved this machinery (`services/snapshots.py`) and the
concept ports directly even though the code does not; it costs nothing in speed
and it is the only thing between a bad run and a client's live website. The
per-run commit also gives WebPro its diff view for nothing.

One real obstacle, known in advance: **the site trees have three different
owners.** Sources live under `/root` (mode 700), published trees under
`/var/www` are `www-data`, and the sandbox clones are `sitebuilder`. Connecting
as root sidesteps it but makes every WebPro run a root run on a box serving 17
client sites. Decide the user and the writable paths deliberately before the
first live edit, not after — this is the same ownership confusion that already
broke the clones' git remotes once and produced
`/usr/local/sbin/sb-clone-sync`.

---

## Phase 4 — AppPro

The part of the original ask with the most novelty: one concept, planned once,
then decomposed into **20–30 AI-executable phases plus a human to-do list**.

That decomposition is the actual product, and the studio has already proved the
parts in miniature: a brief becomes a plan (`services/brief.py` →
`prompts.plan_prompt`), a plan is approved, a build runs against it, and the
playbook rides along in every prompt. AppPro is that loop with three targets and
a longer spine.

**"Visual" here means a map of the app you can steer, not a pixel canvas** —
screens, data flow, API calls and state as a graph, with AI filling in each
node. This is the better of the two readings, because the map and the phase plan
are then *the same object* rather than two things to keep in sync: a node is a
phase, an edge is a dependency, and the order the graph can be walked is the
order the phases can run. It is also the only version that holds a large concept
together across 20–30 steps, which is the stated problem. The cost is that it is
weak at "make that button a warmer orange" — so the point-and-describe mechanism
(the studio's existing `services/marks.py`) stays the tool for appearance, and
the map is the tool for structure.

**All three ecosystems from day one.** Not web-first, not iOS-first: a concept
is planned once and the phase plan covers web, iOS and Android together, so the
map is never a map of one platform that has to be re-derived for the others. The
cost is accepted deliberately — every phase carries three sets of build
problems, and the first real app pays all of them at once.

**AppPro itself is SwiftUI**, like the rest of LodiStudios — and **the apps it
produces are native per platform**: SwiftUI for iOS and Mac, Kotlin with Compose
for Android, a web stack for the browser. Three codebases per app, not one
cross-platform one.

That sounds like heresy only because of who used to write the code. Three
codebases were unthinkable when humans maintained them by hand; when the map is
the source of truth and AI generates each implementation from it, the objection
largely dissolves — and what you get back is a genuinely native result on every
platform instead of the usual cross-platform tax.

It also makes the map load-bearing rather than decorative. If the map is the
only shared artifact, it has to carry everything the three implementations must
agree on: screens, navigation, data shapes, API contracts, state transitions,
validation rules and copy. That is a real design constraint on Phase 4 and the
thing most likely to be underestimated — **drift between the three
implementations is this phase's central risk**, and the map plus per-platform
conformance checks are the mitigation.

**The human to-do list is the feature nobody else builds.** This session alone
produced four items no model can do: get the Bluehost login to change a DNS
record, obtain emails for three people, decide whether a client pays before
their refresh ships, buy an Apple Developer account. A plan that silently
assumes those are done is a plan that stalls. Each phase should declare its
human prerequisites, and the app should track them as first-class items.

Targets, with the constraint stated honestly:
- **iOS** — first. Buildable *only* on the Mac; the droplet could never do it at
  any size. Needs Xcode and an Apple Developer account ($99/yr) to reach a
  device or the store. That account is itself a Phase-4 human to-do item.
- **Android** — buildable on the Mac. Needs a JDK, the Android SDK and Gradle
  (8–15 GB), and a Play Console account ($25 once). Not viable on the droplet:
  Gradle wants more RAM than the box has in total.
- **Web** — buildable on the Mac or the droplet today.

---

## Phase 5 — LodiAdmin

Last for a reason: two of its three halves have no foundation yet.

- **Droplets** — needs a DigitalOcean API token; none exists anywhere on the
  box, and `doctl` is not installed.
- **DNS** — the one part with real foundations. `/usr/local/bin/gd-dns` already
  speaks the GoDaddy v3 API with deliberate safety rails (refuses the zone apex;
  `rm` only deletes records pointing at this server's own IP). It is single-zone
  and GoDaddy-only, so multi-client work needs multi-zone handling and probably
  a second provider — this week alone involved a Bluehost zone and a Google
  Domains zone.
- **Analytics** — no data source of any kind exists. Decide what it should
  measure before building anywhere to put it.
- **Security** — `fail2ban`, `unattended-upgrades` and `sysstat` are running and
  unsurfaced; the studio's own audit log already exists and has a page.

---

## Verification

Each phase carries its own, but the standing ones:

- `cd /srv/sitebuilder/bot && sudo -u sitebuilder .venv/bin/python -m pytest -q`
  — currently **562 passed**. Any work touching the studio keeps it green.
- Nothing in that repo is written as root: `find . -path ./.venv -prune -o
  ! -user sitebuilder -print` must print nothing. (The repo's `CLAUDE.md` now
  carries this rule, because three agents broke it in one session.)
- For LodiTerminal, the honest test is use: the owner runs it instead of Termius
  for a week. Perpetual sessions are verified by closing the laptop and coming
  back, not by a unit test.

## Risks worth naming now

1. **Scope.** Five products is years of work, not weeks. The sequencing above is
   the mitigation: each phase has to be independently useful, and the order is
   chosen so that nothing later is blocked by something unbuilt.
2. **The droplet's ceiling.** The Green Flash box is 2 vCPU / 3.8 GB / 80 GB (the
   $24 tier), idle most of the time but swapping through every Next.js build and
   every parallel Claude session. Measured 2026-09-18: 1.2 GB in use, 2 GB of
   stale swap, load 0.17. Resize it to 4 vCPU / 8 GB for builds, and give
   LodiStudios its own 4 vCPU / 8 GB session droplet rather than sharing.
3. **Native SwiftUI means no UI reuse.** WebPro's pages are HTML and stay that
   way. If AppPro later wants the same visual editor in both places, it gets
   written twice. That is the accepted cost of a genuinely native Mac app.
6. **No App Store is needed, and none is ruled out.** The embedded core runs
   sandboxed, so the Mac build can be Developer ID *or* App Store, and the iOS
   build installs through the owner's Developer account. Keychain items are
   still bound to one signing identity: settle on it before storing a single
   secret.
7. **Three native codebases per app can drift.** Phase 4's map has to carry
   every contract the three implementations share, or they diverge quietly.
8. **The brand palette is a logo strategy, not a UI strategy.** Four saturated
   primaries used evenly makes an unreadable toy. Black and white carry the
   interface; one primary per tool does the pointing. If that discipline slips,
   the app will look wrong and nobody will be able to say why.
9. **The logo and lodistudios.com currently disagree** on the entire palette.
   Settle which is the brand before building a design system on either.
4. **An SSH tool holds the keys to client infrastructure.** Agent forwarding
   keeps key material off the droplet, but the Mac app itself becomes a
   high-value target. Keychain, not a config file, and no exceptions.
5. **The infrastructure product acts on servers we do not own.** A read-only
   default and an explicit approval gate are not optional politeness; they are
   what makes it sellable.
