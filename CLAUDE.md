# LodiStudios — standing rules for every session in this repo

Read `docs/plan.md`, `docs/ui-review.md` and `docs/requests.md` before designing or building
anything. They are the spec; a decision recorded there is not reopened without the owner.

## What this is
A native SwiftUI app for one user (the owner) on macOS and iOS: LodiTerminal, WebPro, AppPro,
Infrastructure Pro, LodiAdmin, plus the Board, the Run view, ⌘K and the Assistant. Completely
separate from the Green Flash web studio; the two never share runtime code or servers.

## Rules the owner has set
- **Models:** Opus, Sonnet or Haiku for all work, including subagents (pass `model` explicitly).
  Fable only with the owner's explicit permission for that run.
- **Backups, not gates:** no approval steps on the owner's own live work. Every change is committed
  and pushed to GitHub; "go back one version" must be one action.
- **Separate products:** never propose folding this into the Green Flash studio, or aligning its
  branding with lodistudios.com. The app follows the logo (`docs/logo.png`); the site is its own thing.
- **Log the gaps:** when the owner asks for something the app does not have, add it to
  `docs/requests.md` in his words, with where he was and the status, in the same turn.
- **Capture concepts:** corrections and named concepts go into these docs (or code comments)
  with their *why*, so the next session gets it right first time.
- **Small fan-out:** about two agents on a build, not twelve.

## Architecture decisions already made (see docs/plan.md)
- One embedded `libssh2` core for Mac and iOS; the app is its own SSH agent (Unix socket in the
  sandbox, Keychain / Secure Enclave keys, destination constraints enforced in-app). No spawned `ssh`.
- Sessions persist in tmux on a dedicated LodiStudios session droplet; the Green Flash droplet
  stays client-facing and is just another host.
- `CommandRegistry` in week one: every toggle, button, menu item and shortcut is a registered
  Command. Views invoke commands and have no bare actions. The Assistant, ⌘K, App Intents,
  widgets, notifications and the `lodi` CLI all read the registry.
- `PaneOutputSink` / `PaneWriter` in week one. SwiftTerm for rendering on both platforms.
- Design system: black ground, white text, one logo primary per tool in chrome only; status
  colours separate from tool accents; the site's pink is the Assistant's colour and appears
  nowhere else. Dark only.

## Build order
v0.1 terminal + Board (read-only) + ⌘K + CommandRegistry + Assistant (navigate, invoke, log
requests) + push relay. Then v0.2 SFTP / iOS parity / Live Activities / widgets, v0.3 control
mode / FileProvider / on-device routing, v0.4 editing / constraints UI / Mosh.

## Verification
Build with `xcodebuild` (or `swift build` for LodiKit) and run the LodiKit tests before
reporting. Prove the Secure Enclave sign round-trip against the session droplet in week one.
