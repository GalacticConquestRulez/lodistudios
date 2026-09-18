# Hosts

| Host | Role | Public IP | Private IP (VPC nyc1) | OS | Host key (ED25519) |
|---|---|---|---|---|---|
| **greenflash** | client-facing: 17 sites, Green Flash Studio, its own Claude runner | 142.93.198.162 | 10.116.0.2 | Ubuntu 26.04 LTS | `SHA256:O01ThyuNFaUU+3eGESaMK5hF4q1a6pkIyWtSGF9UtM4` |
| **Sessions** | LodiStudios session droplet: tmux, the owner's Claude Code runs, push relay, `lodi` CLI | 67.205.136.45 | 10.116.0.6 | Ubuntu 26.04 LTS | `SHA256:QSNdYT45PqF23pHNBeg92CL/Qj0XDfpYm9hZc/4CfJU` |

Both in DigitalOcean nyc1 on the $24 tier (2 vCPU / 4 GB / 80 GB), same VPC, so the hop from
Sessions into greenflash can use the private address.

## Sessions — as set up on 2026-09-18
- ufw: default deny in, `OpenSSH` allowed — the allow rule runs *before* enable, always
  (the first attempt at this box locked SSH out by enabling with no rule; it was rebuilt).
- fail2ban, unattended-upgrades; sshd keys-only, `PermitRootLogin prohibit-password`.
- 4 GB swapfile, `vm.swappiness=10`.
- `cc`, `cc-sessions`, `cc-sessions.service`, `cc-sessions-save.timer` copied from greenflash;
  `~/.tmux.conf` likewise, plus `~/.ssh/rc` re-pointing `~/.ssh/agent.sock` at each login's
  forwarded agent and tmux exporting that stable path, so `git push` inside a reattached
  session keeps working.
- Claude Code 2.1.275 via the native installer (`~/.local/bin/claude`).
- Keys authorised: `greenflash-droplet` (this is the GF box's root key — **remove it** once the
  Mac and the app's per-device keys drive this box; the trust should point Sessions → greenflash,
  never the reverse), `Termius` (the owner's).

## To do
- [ ] Sign Claude Code in on Sessions (owner's choice: copy greenflash's credentials, or log in there).
- [ ] Restrict greenflash's sshd to the VPC address of Sessions plus the owner's devices.
- [ ] Remove `greenflash-droplet` from Sessions' `authorized_keys` when the app's keys are in place.
- [ ] Reserved IP for Sessions (free while attached) so a future rebuild keeps its address.

## Device keys authorised on Sessions
| Device | Key | Fingerprint | Added |
|---|---|---|---|
| Tanner's MacBook Pro (M1 Max) | ed25519, app-generated, held in the Keychain (`SSHKeyStore`) | `SHA256:1JUiz4wxCARiVJk8y2h5BGyl0BJ5oCfI+6pB/C6PZh4` | 2026-09-18 |

The iPhone gets its own key when the iOS build first runs; never copy a key between devices.
Note on M1's key: ed25519 is a CryptoKit key stored as Keychain data (SecKey has no ed25519),
so it is loadable in-process; the non-extractable key is the Secure Enclave P-256 one at
milestone 5. The store's own comment says the same.
