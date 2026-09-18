# Review — f62fecc, transport milestone 2a: the in-app agent server

**Verdict: correct, with one parse to fix before v0.4 relies on it.** Constants right, framing
right, `IDENTITIES_ANSWER` right, `SIGN_RESPONSE` carries the *full* signature
(`string(alg) ‖ string(blob)`) while libssh2's callback gets the inner blob — the distinction
`agentSignature` exists for, and the one most implementations get wrong once. The responder
is pure and tested with a fake signer; the socket is framing only. Good shape.

## Fix (small, do it before M2b's forwarding test)
`session-bind@openssh.com` carries **four** fields after the extension name, in this order:
`string hostkey`, `string session identifier`, `string signature`, `bool is_forwarding`
(OpenSSH `PROTOCOL.agent`). The code takes the *first* string as the session id — that is the
**host key**, not the session identifier. Read all four; record `(hostkey, sessionID,
isForwarding)`. Enforcement is v0.4, but the recorded value must be the right one now, or v0.4
starts from wrong data and nobody notices until a constraint fails to bind.

## Notes, none blocking
- Set the socket to mode `0600` right after `bind` (`chmod`), even though the container
  directory is already private. Belt and braces on the thing that signs with your key.
- One client at a time. Correct for v0.1 (agent traffic is sequential), but a forwarded agent
  channel from a stalled remote shell would block local authentication. When M3 makes sessions
  long-lived, serve each accepted client on its own thread or a dispatch queue.
- `stop()` ends the accept loop but not a client mid-conversation; acceptable now.

M2b next: `libssh2_agent_set_identity_path(socketPath)`, authenticate through the agent instead
of the callback, then `libssh2_channel_request_auth_agent` on a shell channel and prove it —
`ssh-add -l` on Sessions listing the Mac's P-256 key.
