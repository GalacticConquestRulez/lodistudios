import SwiftUI
import LodiKit

/// The Board — the live front page: what is running, broken, waiting. v0.1 shows
/// the host inventory read-only; runs and status land as the transport does.
struct BoardView: View {
    let hosts: [Host]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Board")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(LodiTheme.text)

                Text("Hosts")
                    .font(.headline)
                    .foregroundStyle(LodiTheme.secondaryText)

                ForEach(hosts) { host in
                    HostRow(host: host)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct HostRow: View {
    let host: Host

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "circle.fill")
                .font(.system(size: 8))
                .foregroundStyle(LodiTheme.secondaryText)
            VStack(alignment: .leading, spacing: 2) {
                Text(host.alias)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(LodiTheme.text)
                if let role = host.role {
                    Text(role)
                        .font(.caption)
                        .foregroundStyle(LodiTheme.secondaryText)
                }
            }
            Spacer()
            Text(host.hostName)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(LodiTheme.secondaryText)
        }
        .padding(12)
        .background(LodiPalette.paper.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
}
