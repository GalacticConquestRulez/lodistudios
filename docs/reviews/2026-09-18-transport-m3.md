# Review — 1ab75cd, milestone 3 (transport half): SSHTerminalSession

**Verdict: right shape — dedicated thread, PTY, `tmux new -A`, broadcaster out, `PaneBackend`
in, resize through `request_pty_size_ex`, the M1/M2 paths reused.** Two defects to fix before
the view is wired, because they only show up with a human typing or a second tab open.

## 1. `libssh2_init` / `libssh2_exit` per session will crash the second tab
`loop()` calls `libssh2_init` on entry and `libssh2_exit` in its `defer`. The first tab to close
tears down libssh2's global state under every other live session (and under any `SSHSession.run`
in flight). Initialise **once per process** (a `static let` / `dispatch_once`) and never call
`libssh2_exit` — the M1 note said this for M3, and M3 is now.

## 2. Keystrokes can lag up to five seconds on an idle shell
`eventLoop` blocks in `waitSocket` (`poll`, 5 000 ms) whenever nothing progressed. A keystroke
queued by `sendBytes` during that wait is not written until `poll` returns — so on an idle
prompt, each key can take up to 5 s to echo. Same for `stop()` and `resize`. Fix: the self-pipe
trick — a `pipe()` whose read end sits in the same `poll` set as the socket; `sendBytes`,
`resize` and `stop` write one byte to the write end; the loop drains it on wake. Do not "fix"
this by shortening the poll timeout; that trades latency for a busy loop on every idle tab.

## Smaller
- `writeAll` spins on `EAGAIN` (`continue` without waiting). `waitSocket` on EAGAIN.
- The tmux session name is hardcoded `lodi`. Make it a parameter, default `lodi-<host alias>`,
  so two tabs to one host are two sessions unless the user asks to share one. (`cc` on the
  droplet names sessions by directory; the app can adopt that convention for "attach to an
  existing session" later.)
- On channel EOF the loop ends and `onClosed(nil)` fires — correct for a tmux detach. The tab
  should offer *Reattach* rather than close; that is M4's banner in embryo.

## For M6, note now so the shape is right
The terminal channel neither requests `auth-agent` nor services agent channels, so `git push`
or `ssh greenflash` *inside* the tmux session will find no agent — and the terminal is where the
onward hop matters most. Factor the agent-channel servicing out of `runExec` into a shared
helper and call it from `eventLoop` too; request `auth_agent` on the PTY channel. Not for this
commit; recorded so M6 does not rediscover it.

Proof for the milestone stays: `cc -l` renders, keys echo without lag, `htop` draws, a second
tab opens and the first keeps working.

---

# 23f380c — M3 (UI half): SwiftTerm wired

**Verdict: the wiring is right — the view is one `PaneOutputSink`, output hops to the main
thread, resize flows back, one renderer on both platforms, per-agent socket paths so a terminal
and a probe can coexist.** Three things, in order of importance:

1. **The transport fixes above are still not in** (`libssh2_exit` ×2, no self-pipe, session name
   hardcoded). This commit landed before the review was pulled. Do them now, before the first
   real typing session — the 5-second keystroke lag will be the first thing the owner notices.
2. **Keystrokes bypass `PaneWriter`.** `send(source:data:)` calls `session.sendBytes` directly.
   The session is already a `PaneBackend`, so this is one line: hold a
   `PaneWriter(backend: session)` in the coordinator and `write(.text(...))` through it. The
   whole point of the week-one seam is that there is exactly one door for input — a human's
   keys and an agent's `send-keys` alike — with a policy in front. Don't let the first caller
   walk around it.
3. **The session dies with the view.** `TerminalModel` lives in `@State` on `LodiTerminalView`
   and `onDisappear` stops the session, so switching to the Board and back disconnects and
   reconnects. tmux makes that survivable, but M4 (reconnect as a non-event) and the Board
   (sessions as first-class objects) both need sessions that outlive views: an app-level,
   `@Observable` session store keyed by host/tab, injected like the registry; views attach and
   detach *sinks*, never start or stop sessions. Do it as part of M4, not now — but don't build
   more on the `@State` shape.

Smaller: the terminal is hardcoded to the `sessions` host; fine for v0.1, the host list comes
with tabs. `try? agent.start()` swallows a failure that would make every connection fail with
a confusing auth error — surface it.

---

# a4ab097 — M3 proven; the review items are still open

**Seen from Sessions, 2026-09-18 06:10:19 UTC:** `tmux ls` → `lodi: 1 windows (created Fri Sep
18 06:10:19 2026) (attached)`. The app's terminal is attached to a real tmux session on the
droplet through embedded libssh2, its own agent, and SwiftTerm — on the Mac. That is the
milestone: a terminal you type into, with the session living in the cloud. Closed as proven.

**Not yet done, and they matter before daily use:** `libssh2_exit` still called per session
(second tab will crash the first), no self-pipe (idle-prompt keystrokes wait for `poll`),
keystrokes bypass `PaneWriter`, session name hardcoded `lodi`. The commits since the review
landed without pulling it. Pull, do the four, then M4.

**Observed on the Mac, 2026-09-18:** "5 second delay between keystrokes" on an idle prompt —
exactly the `poll` timeout. Fix 2 (self-pipe wake) is confirmed as the cause, not the network.

---

# 3805df6 — the four fixes, verified

All four done and done right: `LibSSH2.ensure()` behind a `static let` (the only remaining
`libssh2_exit` is in a comment saying never to call it); a non-blocking self-pipe in the poll
set, woken by `sendBytes`, `resize` and `stop`, drained on wake; `writeAll` waits on EAGAIN;
session name `lodi-<host alias>` by default and settable per tab; keys through
`PaneWriter(backend: session)`. **M3 closed.**

One small thing for M4, not a blocker: keys are converted `[UInt8] → String → [UInt8]` on the
way through `PaneInput.text`. A multi-byte character split across two `send` calls would be
mangled by the lossy decode. Add a `PaneInput.bytes([UInt8])` case for raw input and use it from
the terminal view; `.text` stays for the Assistant and `send-keys`.
