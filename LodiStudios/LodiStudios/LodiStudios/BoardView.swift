import SwiftUI
import LodiKit

/// The Board — the live front page: what is running, broken, waiting
/// (docs/ui-review.md, gap 1). v0.1 shows each host with its operational facts;
/// the data comes from a HostFactsProvider (fake now, SSH-backed once the
/// transport lands), so the Board never changes when real data arrives.
struct BoardView: View {
    let hosts: [LodiKit.Host]

    @Environment(\.hostFacts) private var provider
    @State private var facts: [String: [HostFact]] = [:]

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
                    HostCard(host: host, facts: facts[host.alias] ?? [])
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: hosts.map(\.alias)) {
            // Refresh on a loop so the Board stays live and picks up facts once the
            // agent is ready; each host fills in as its facts return.
            while !Task.isCancelled {
                for host in hosts {
                    facts[host.alias] = await provider.facts(for: host)
                }
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }
}

private struct HostCard: View {
    let host: LodiKit.Host
    let facts: [HostFact]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
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

            if !facts.isEmpty {
                Divider().overlay(LodiPalette.paper.opacity(0.08))
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(facts) { fact in
                        FactRow(fact: fact)
                    }
                }
            }
        }
        .padding(14)
        .background(LodiPalette.paper.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// A single fact: shape + word carry the status, colour only reinforces it, from
/// the status trio and never a tool accent (docs/ui-review.md, gap 4).
private struct FactRow: View {
    let fact: HostFact

    var body: some View {
        HStack(spacing: 10) {
            Text(fact.status.symbol)
                .font(.caption)
                .foregroundStyle(color(for: fact.status))
                .frame(width: 14)
            Text(fact.label)
                .font(.callout)
                .foregroundStyle(LodiTheme.secondaryText)
                .frame(width: 70, alignment: .leading)
            Text(fact.value)
                .font(.callout)
                .foregroundStyle(LodiTheme.text)
            Spacer(minLength: 0)
        }
    }

    private func color(for status: HostFact.Status) -> Color {
        switch status {
        case .ok:      LodiTheme.statusOk
        case .warn:    LodiTheme.statusWarn
        case .fail:    LodiTheme.statusFail
        case .unknown: LodiTheme.secondaryText
        }
    }
}

// MARK: - Provider injection

private struct HostFactsProviderKey: EnvironmentKey {
    static let defaultValue: any HostFactsProvider = FakeHostFactsProvider()
}

extension EnvironmentValues {
    /// The Board's source of facts. Defaults to the fake provider; swap to the
    /// SSH-backed one at the app root once the transport is live.
    var hostFacts: any HostFactsProvider {
        get { self[HostFactsProviderKey.self] }
        set { self[HostFactsProviderKey.self] = newValue }
    }
}
