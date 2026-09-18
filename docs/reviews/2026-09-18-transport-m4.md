# Review — a041459, milestone 4: disconnect is not an event

**Verdict: the right shape, and it closes the M3 UI item too.** A reconnecting loop with
1/2/4/5 s backoff and an interruptible sleep on the wake pipe; a read error becomes a reconnect,
a clean EOF a reattach; `tmux new -A` brings scrollback back from the droplet; state reported
as connecting / connected / disconnected(reason). `TerminalStore` is the app-level owner keyed
by host — views attach sinks and never start or stop sessions — which is exactly what the M3
review asked for. The banner carries status as shape + word with the status trio.

**Seen from Sessions:** `lodi-sessions` created 06:19:58 and attached (per-host naming working),
and six app logins between 06:10 and 06:19 — reconnections happening in practice.

## Missing from the spec, do before calling M4 closed
- **tmux server restart is not detected.** `tmux new -A` silently creates a fresh, empty session
  when the old one is gone, and the owner cannot tell that from a reattach — the spec says to
  *say so* rather than show an empty pane. Cheapest honest check: before the attach, exec
  `tmux has-session -t <name>` (separate exec, same session); if it fails and the store has seen
  this host connected before, report `.disconnected(reason: "tmux session '<name>' is gone —
  previous output not available")` once, then attach anyway.
- **Proof still owed:** Wi-Fi off → banner with the reason → Wi-Fi on → reattached with the
  scrollback intact and no keystrokes lost. The logins show reconnects; the spec wants the
  drop-and-return exercised deliberately.

## Smaller
- The banner shows `"\(error)"` raw — `Failure.description` is readable enough, but strip the
  `handshake:`/`socket:` prefixes for the banner and keep them for the log.
- A deliberate detach (Ctrl-a d) reattaches within a second, which makes detaching from inside
  the app impossible. Acceptable — closing the tab is how you leave — but say so in a comment.
- `PaneInput.bytes([UInt8])` from the M3 note is still open; fold it in here.
- The stale `lodi` session from the pre-rename run is being cleaned up from the droplet side.

Then M5 (Secure Enclave — one attribute on the same SecKey path) and M6 (the onward hop, which
needs `auth_agent` requested and serviced on the terminal channel — see the M3 review).

---

# 993c0e3 — device key moved to the data-protection keychain

Right fix for a real problem: Xcode re-signs a debug build on every build, so a login-keychain
ACL never matched twice and every signature prompted. The data-protection keychain scopes the
key to the entitlement group instead — no prompt, survives rebuilds, and it is the keychain the
Secure Enclave key lives in at M5, so M5 is now genuinely one attribute away. The fresh key
(`SHA256:CZNfy3+…`) is authorised on Sessions; the old one is removed.

**Still open from M4:** tmux-restart detection (`has-session` before the attach) and the
drop-and-return proof; `PaneInput.bytes` from M3. None of the three are in this commit.

**Confirmed by use, 2026-09-18 17:47–17:51:** the rebuilt app signed in to Sessions with the
data-protection-keychain key (`SHA256:CZNfy3+…`) with no signing prompt, and the owner then
edited a file in nano over the session — "this worked well." That closes the keystroke-lag
item from M3 in practice: nano is unusable at five seconds a key. **Still owed for M4:** the
deliberate Wi-Fi drop-and-return, and tmux-restart detection.

**Drop test, 2026-09-18 — a blip survived, the reconnect path not yet exercised.** Wi-Fi off,
then on; "same session back." But Sessions' log shows **no new login** after the 17:47 one, and
a reconnect is always a new TCP connection. So the outage was short enough that the existing
TCP connection survived it: nothing was sent, nothing timed out, the same connection resumed.
Correct behaviour for a blip — and no banner because nothing disconnected — but M4's loop has
not run for real yet, and the test exposed a gap:

**Add SSH keepalives.** Without them a *dead* link (hotspot switch, router reboot, lid closed
for an hour) is only noticed when a write fails, which can be many minutes. In `connectAndServe`:
`libssh2_keepalive_config(session, 1, 15)` after the handshake, and call
`libssh2_keepalive_send(session, &secondsToNext)` from the event loop (use its return value as
the poll timeout instead of the fixed 5 000 ms). Two missed keepalives → libssh2 errors →
the loop reconnects within ~30 s of a real drop, with the banner.

**The proof, properly:** Wi-Fi off for a full **two minutes**, terminal open. Expected: within
~30 s the banner says why; Wi-Fi on; the session reattaches and Sessions' log shows a fresh
`Accepted publickey … CZNfy3+…`. That login line is the evidence; ask the droplet session to
read it.

Remaining from M4's list: tmux-restart detection, `PaneInput.bytes`. Then M5 (Secure Enclave —
`kSecAttrTokenIDSecureEnclave` on the same data-protection-keychain path) and M6 (the onward
hop: `auth_agent` requested and serviced on the terminal channel).
