# Review — c9a69d4 + a0b4f87: the Board is honest, and v0.1 is closed

**Verdict: accepted.** Both notes from the close-out review are answered in the code, and
the proof is in the droplets' own logs.

- `c9a69d4` — no fake fallback anywhere in a production path. `Host.directHostName` is the
  right shape: the inventory keeps the VPC address for the Sessions → greenflash hop and gives
  the Mac a public address to dial. A host with neither shows one honest `Reachability` fact
  with `.unknown`, and an unreachable host is `.unknown` rather than `.fail` — correct, because
  "we could not ask" is not "it is down".
- `a0b4f87` — 60 s loop, `as of HH:MM:SS` on the card, refresh on `scenePhase == .active`.

**Proof from greenflash's journal (2026-09-19 UTC):** Board probes now arrive directly from the
Mac (`38.49.92.35`, the Enclave ECDSA key `SHA256:48ov0n3C…`) — the first direct logins
greenflash has ever seen from the Board. Between 01:27 and 01:32 they came every ~17 s on both
droplets, which is the *old* 15 s build; nothing after 01:34, so either the 60 s build was not
yet running or the app was closed. Confirm with one look at the journal the next time the app
is open: `journalctl -u ssh --since -10min | grep Accepted` should show one login per host per
minute, no more.

**Reconnect proof, pending the owner's word.** Sessions' journal shows four simultaneous logins
at 01:32:12, then silence for 2 m 22 s, then two logins at 01:34:34 — the shape of a Wi-Fi drop
and a reconnect. If the owner's Wi-Fi went off at about 01:32 and back on at about 01:34, this
is the two-minute proof and M4 is fully closed. If not, the test is still owed.

## v0.1 is closed. Next: v0.2

Per `docs/plan.md` "Build order": **v0.2 — SFTP and the iPhone at parity.** One week.

1. **SFTP over the existing session** (`libssh2_sftp_*`, no new connection): a Files pane per
   host — list, navigate, sizes, mtimes, permissions; download to a chosen folder; upload;
   drag from Finder onto the pane to upload into the current directory; drag out to download;
   rename, delete (confirm), mkdir. Transfers through one `TransferQueue` with progress and
   cancel, so the terminal stays responsive. Every operation is a registered `Command` (the
   Assistant and ⌘K get them for free) with `destructive: true` on delete and overwrite.
2. **iPhone parity.** Same LodiKit, same SwiftTerm. Touch chrome: a keyboard accessory bar
   (Esc, Tab, Ctrl, arrows, `|`, `-`, `/`, `~`), pinch to change the font size, tap-to-focus,
   long-press paste, and the extra-keys row hides with the keyboard. The Board and Files pane
   in iPhone layout. Install on the owner's phone through the free 7-day provisioning;
   re-deploy weekly. The location keep-alive switch waits for v0.4 as planned.
3. **Small, because it is cheap now:** an `ssh_config` *export* (never import) so Terminal and
   git on the Mac can use the same hosts and the Enclave key through the app's agent socket.

Rules unchanged: keys through `PaneWriter`, output through `PaneOutputSink`, one agent per app,
agent forwarding untouched, tests for every parser and for the SFTP path listing against real
droplet output, commit messages that say why, pull before every task and every commit.
