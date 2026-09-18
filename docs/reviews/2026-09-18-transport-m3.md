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
