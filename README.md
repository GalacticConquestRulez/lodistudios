# LodiStudios

Native SwiftUI homebase for the owner's tools — macOS and iOS. Spec lives in `docs/`.

## Setting up the Mac (M1 Max)
1. **Xcode 26** from the App Store, then `sudo xcodebuild -license accept` and
   `xcodebuild -runFirstLaunch`. Install the iOS 26 simulator runtime when prompted.
2. **Apple Developer account**: Xcode → Settings → Accounts → add the Apple ID; set the team on
   the project once it exists. Needed for installs that outlive 7 days, push, CloudKit, TestFlight.
3. **Claude Code**: `curl -fsSL https://claude.ai/install.sh | bash` (or `brew install claude-code`),
   then `claude` once to log in with the same account as the droplet session.
4. **SSH to the session droplet** from the Mac (`~/.ssh/config` entry), so the app under test has
   a real host to attach to.
5. `git clone` this repo, `cd LodiStudios`, run `claude`. Optionally `/remote-control` so the
   phone can drive the Mac session. The first prompt: *"Read CLAUDE.md and docs/, then scaffold
   LodiKit and the app targets for v0.1."*

## Layout (to be created on the Mac)
- `LodiKit/` — Swift package: SSH core (libssh2 xcframework), in-app agent, CommandRegistry,
  Board data layer, run-transcript parser, Assistant client, design tokens.
- `LodiStudios/` — the app: macOS and iOS targets sharing LodiKit.
- `scripts/` — `build-libssh2.sh` (xcframework for iOS/macOS), `lodi` CLI for the droplet.
- `docs/` — plan, UI review, requests log, logo.
