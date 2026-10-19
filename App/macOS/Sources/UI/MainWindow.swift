import SwiftUI

enum Page: String, CaseIterable, Identifiable, Hashable {
    case dictation, styles, notes, setup, settings
    var id: Self { self }

    var title: String {
        switch self {
        case .dictation: "Dictation"
        case .styles: "Styles"
        case .notes: "Notes"
        case .setup: "Setup"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .dictation: "keyboard"
        case .styles: "paintbrush.pointed"
        case .notes: "book.closed"
        case .setup: "checkmark.shield"
        case .settings: "gearshape"
        }
    }
}

/// Sidebar window: Dictation home plus setup and settings.
struct MainWindow: View {
    @Bindable var app: AppModel

    var body: some View {
        NavigationSplitView {
            Sidebar(app: app)
                .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            Group {
                switch app.page {
                case .dictation: DictationPage(app: app)
                case .styles: ComingSoonPage(title: "Styles", symbol: "paintbrush.pointed", message: "Turn what you say into a diary entry, a professional summary, or text in your own voice.")
                case .notes: ComingSoonPage(title: "Notes", symbol: "book.closed", message: "Long recordings become notes in your Obsidian vault, synced through Nextcloud.")
                case .setup: SetupView(app: app)
                case .settings: SettingsView(app: app, embedded: true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.background)
        }
        .frame(minWidth: 860, minHeight: 620)
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    }
}

private struct Sidebar: View {
    @Bindable var app: AppModel

    var body: some View {
        List(selection: Binding(get: { app.page }, set: { if let page = $0 { app.page = page } })) {
            Section {
                row(.dictation)
                row(.styles, soon: true)
                row(.notes, soon: true)
            }
            Section {
                row(.setup)
                row(.settings)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 10) {
                // From the bundle directly: the system's cached app icon can be a stale placeholder.
                Image(nsImage: Bundle.main.image(forResource: "AppIcon") ?? NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 34, height: 34)
                Text("Audio Pencil")
                    .font(.system(size: 18, weight: .semibold, design: .serif))
                    .lineLimit(1)
                    .fixedSize()
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 10)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Label("Private, on-device", systemImage: "lock.fill").foregroundStyle(.secondary)
                Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")")
                    .foregroundStyle(.tertiary)
            }
            .font(.caption)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    private func row(_ page: Page, soon: Bool = false) -> some View {
        HStack {
            Label(page.title, systemImage: page.symbol)
            Spacer()
            if soon {
                Text("Soon").font(.caption2.weight(.medium)).foregroundStyle(.secondary)
            } else if page == .setup, app.needsSetup {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
            }
        }
        .tag(page)
    }
}
