import Foundation
import CLibSSH2

/// Servicing for forwarded `auth-agent@openssh.com` channels — the app's agent
/// reached from a remote shell (docs/reviews/2026-09-18-transport-m2.md and -m3).
/// Shared by the one-shot exec path (SSHSession) and the interactive terminal
/// (SSHTerminalSession), so `ssh-add -l`, `git push` and `ssh greenflash` inside a
/// tmux session all reach the same in-process responder. No socket on this path.
///
/// Holds the channels the server opened plus the responder that answers them,
/// reached from the C callback via the session abstract.
final class AuthAgentContext {
    var responder: SSHAgentResponder
    var channels: [OpaquePointer] = []
    var buffers: [OpaquePointer: [UInt8]] = [:]
    init(responder: SSHAgentResponder) { self.responder = responder }
}

/// LIBSSH2_CALLBACK_AUTHAGENT: the server opened an `auth-agent@openssh.com`
/// channel (libssh2 has already confirmed it). Record it; the caller's loop
/// services it via `AuthAgentForwarding.service`.
func lodiAuthAgentCallback(
    _ session: OpaquePointer?,
    _ channel: OpaquePointer?,
    _ abstract: UnsafeMutablePointer<UnsafeMutableRawPointer?>?
) {
    guard let channel, let ctxPtr = abstract?.pointee else { return }
    let context = Unmanaged<AuthAgentContext>.fromOpaque(ctxPtr).takeUnretainedValue()
    context.channels.append(channel)
    context.buffers[channel] = []
}

enum AuthAgentForwarding {
    /// Register the auth-agent callback so libssh2 confirms and hands us the
    /// server-opened forwarded channels instead of refusing them. The context is
    /// reached through the session abstract, set at `libssh2_session_init_ex`.
    static func registerCallback(on session: OpaquePointer) {
        let typed: @convention(c) (
            OpaquePointer?, OpaquePointer?, UnsafeMutablePointer<UnsafeMutableRawPointer?>?
        ) -> Void = lodiAuthAgentCallback
        let generic = unsafeBitCast(typed, to: (@convention(c) () -> Void).self)
        libssh2_session_callback_set2(session, LIBSSH2_CALLBACK_AUTHAGENT, generic)
    }

    /// Pump each forwarded auth-agent channel: read bytes, split on the 4-byte
    /// length frame, answer with the responder, write the reply, free on EOF.
    /// Returns whether any bytes moved.
    static func service(_ context: AuthAgentContext) -> Bool {
        var progressed = false
        var readBuffer = [Int8](repeating: 0, count: 4096)
        var closed: [OpaquePointer] = []

        for channel in context.channels {
            let n = libssh2_channel_read_ex(channel, 0, &readBuffer, readBuffer.count)
            if n > 0 {
                var pending = context.buffers[channel] ?? []
                readBuffer.withUnsafeBytes {
                    pending.append(contentsOf: $0.bindMemory(to: UInt8.self).prefix(n))
                }
                while let frame = takeFrame(&pending) {
                    let reply = context.responder.handle(frame)
                    writeChannel(channel, reply)
                }
                context.buffers[channel] = pending
                progressed = true
            } else if n == 0 || (n < 0 && n != LIBSSH2_ERROR_EAGAIN) {
                closed.append(channel)
            }
        }

        for channel in closed {
            libssh2_channel_close(channel)
            libssh2_channel_free(channel)
            context.channels.removeAll { $0 == channel }
            context.buffers[channel] = nil
        }
        return progressed
    }

    /// Split one framed agent message (4-byte length + body) off the front of the
    /// buffer, returning the body; nil if a whole frame isn't buffered yet.
    private static func takeFrame(_ buffer: inout [UInt8]) -> Data? {
        guard buffer.count >= 4 else { return nil }
        let length = (UInt32(buffer[0]) << 24) | (UInt32(buffer[1]) << 16)
            | (UInt32(buffer[2]) << 8) | UInt32(buffer[3])
        guard buffer.count >= 4 + Int(length) else { return nil }
        let body = Data(buffer[4..<4 + Int(length)])
        buffer.removeFirst(4 + Int(length))
        return body
    }

    private static func writeChannel(_ channel: OpaquePointer, _ data: Data) {
        data.withUnsafeBytes { raw in
            let base = raw.bindMemory(to: UInt8.self).baseAddress!
            var sent = 0
            while sent < raw.count {
                let n = libssh2_channel_write_ex(channel, 0, base + sent, raw.count - sent)
                if n == LIBSSH2_ERROR_EAGAIN { continue }
                if n <= 0 { break }
                sent += Int(n)
            }
        }
    }
}
