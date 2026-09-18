# Review — a149454 + 0082145, transport milestone 1: SSHSession

**Verdict: correct, and built the way the spec asked.** Non-blocking from the first call with a
`poll` on `libssh2_session_block_directions()` (issue #535 handled); host key pinned by SHA-256
of the raw key blob in OpenSSH's own fingerprint format, refusing on mismatch; `libssh2_userauth_publickey`
with a sign callback through the `abstract` pointer; the key a non-extractable P-256 `SecKey`
signed with `SecKeyCreateSignature`, with the M5 change reduced to one attribute. The ECDSA
fingerprints are the ones pinned. The Outgoing Connections entitlement is right for a sandboxed app.

## The proof still owed
`exec("uname -a")` against Sessions returning `7.0.0-27-generic`. The P-256 key is authorised
there as of 2f70f1d; the ed25519 line is gone. Sessions' auth log will show
`Accepted publickey for root … ECDSA SHA256:lH2BtBgAl5Bgsa5CO7/vrdiisEjeU9XgSNPkJ1ZHlUg`.

If auth fails with the key clearly installed, look first at `sshSignatureBlob(fromDER:)`: the
SSH blob is `string(mpint r) ‖ string(mpint s)`, and each mpint needs a leading `0x00` when its
high bit is set — libssh2's own `_libssh2_ecdsa_sign` does exactly that. A signature that is
right 50% of the time is that bug.

## Notes for M3, not for now
- The libssh2 flow blocks inside the actor while it polls. Fine for one `exec`; a long-lived
  terminal session must run its I/O loop on its own thread or dispatch queue and post chunks to
  the broadcaster, or the cooperative pool stalls.
- `libssh2_init` / `libssh2_exit` per call — make it once per process when sessions become
  long-lived.
- Unpinned hosts are trust-on-first-use in v0.1. The spec wants the first-connect prompt to be a
  Command so the Assistant can answer it; that lands with the host-add flow.
