# Review — 480cade, transport milestone 0: vendored libssh2 + mbedTLS

**Verdict: good, and verifiable.** libssh2 1.11.1 on mbedTLS 3.6.7, built static for macOS
arm64, iOS arm64 and iOS Simulator arm64, the four archives merged per slice with
`libtool -static`, packaged as an xcframework, vendored under `Vendor/`, exposed to Swift as
`CLibSSH2`, with a linkage test that pins the 1.11 line. The build script pins versions and
verifies SHA-256 before extracting.

## Supply chain, checked independently from the droplet (2026-09-18)
- **mbedTLS 3.6.7** — script pins `a7e8bcbe…11f6`; the official release page's checksum for
  `mbedtls-3.6.7.tar.bz2` is the same value. ✓
- **libssh2 1.11.1** — script pins `9954cb54…3769` for the `.tar.xz` from GitHub releases.
  Downloaded `libssh2-1.11.1.tar.xz` from libssh2.org: same hash. ✓ Cross-check: libssh2.org's
  `.tar.gz` hashes to `d9ec76cb…58f7`, which is what Homebrew's formula pins. ✓
  The script comment says the hash "was computed from the official release tarball" — true, and
  now corroborated by two sources, so it can be trusted as a pin rather than a self-attestation.

## Two things only the Mac can confirm — paste the output
1. `cd LodiKit && swift test` passes, including `LibSSH2LinkageTests`. This proves two things at
   once: that mbedTLS really is inside `libssh2.a` (`libssh2_init` pulls the crypto init, so a
   missing backend fails at link), and that SwiftPM accepts the binary target's
   `../Vendor/libssh2.xcframework` path, which reaches outside the package directory. If SwiftPM
   rejects that path, move `Vendor/` under `LodiKit/` — the script's output path changes, nothing else.
2. An iOS build of the app (Simulator is enough) links — the `ios-arm64-simulator` slice is the
   one most likely to be wrong.

## Notes, none blocking
- Slices are arm64-only, including the Simulator. Correct for an M1 Max; an Intel Mac will never
  run this app and does not need to.
- ~5 MB of static libraries in git is fine at this size. If `Vendor/` grows (Mosh, SwiftTerm
  builds), Git LFS is the move; not now.
- `linkedLibrary("z")` is right — libssh2 is built with zlib compression support.

Milestone 1 next: connect and `exec("uname -a")` against Sessions with a Keychain-held ed25519
key, non-blocking from the first call. The app's public key goes to the droplet session to be
added to `authorized_keys`.
