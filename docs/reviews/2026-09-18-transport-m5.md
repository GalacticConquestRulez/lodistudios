# Review — 614b633, milestone 5: Secure Enclave

**Verdict: correct, and the fallback is the right one.** The Enclave key is preferred and
created on first use with `kSecAttrTokenIDSecureEnclave` and an access control of
`.privateKeyUsage` only — no user-presence flag, so signing never prompts — under its own tag;
if the Enclave is unavailable the data-protection software key is used and M5 becomes a v0.4
item, exactly as the spec allows. `usesSecureEnclave()` exists for the Board to report which
one is in play. Both keys live in the data-protection keychain, so the M4 no-prompt property holds.

## Consequence: a third public key
The Enclave key is a new key. Its public line must be authorised on Sessions before the app can
connect again, and the software key's line comes off once it is — on an M1 Max the Enclave path
always wins, so the software key is dead weight there. The droplet session does both on receipt
of the line; `docs/hosts.md` gets the fingerprint.

## Proof
1. A login in Sessions' log with the new fingerprint.
2. `usesSecureEnclave()` returning true on the Mac — surface it in the Board's facts for the
   host ("key: Secure Enclave" / "key: software"), which is where it belongs anyway.

Then M6: request `auth_agent` on the terminal channel and service agent channels in
`eventLoop` (factor the M2c loop into a shared helper), then `ssh greenflash` from a Sessions
shell — and the agent logs the `session-bind` it received.

---

**M5 proven, 2026-09-18 18:41:49:** Sessions' auth log — `Accepted publickey for root … ECDSA
SHA256:48ov0n3CH6TLc6dCizKw4EaBg9ALQBFwd25QVidLsg4`. The app authenticated with a key generated
inside the Secure Enclave, with no prompt. **M5 closed.**
