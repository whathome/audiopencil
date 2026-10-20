import SwiftUI

enum Page: String, CaseIterable, Identifiable, Hashable {
    case dictation, styles, writing, notes, vault, settings
    var id: Self { self }

    var title: String {
        switch self {
        case .dictation: "Dictation"
        case .styles: "Styles"
        case .writing: "My writing"
        case .notes: "Notes"
        case .vault: "Vault"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .dictation: "keyboard"
        case .styles: "paintbrush.pointed"
        case .writing: "text.quote"
        case .notes: "book.closed"
        case .vault: "externaldrive.connected.to.line.below"
        case .settings: "gearshape"
        }
    }
}

/// Sidebar window. The sidebar collapses to a rail of icons (toolbar button, or automatically when
/// the window is narrow) instead of disappearing.
struct MainWindow: View {
    @Bindable var app: AppModel
    @AppStorage("sidebarCollapsed") private var collapsed = false

    /// Below this window width the sidebar becomes a rail regardless of the toggle.
    private static let railBelowWidth: CGFloat = 760

    var body: some View {
        GeometryReader { geometry in
            let rail = collapsed || geometry.size.width < Self.railBelowWidth
            HStack(spacing: 0) {
                Sidebar(app: app, rail: rail)
                    .frame(width: rail ? 64 : 220)
                    .background(SidebarMaterial().ignoresSafeArea())
                Divider().ignoresSafeArea()
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(.background)
            }
            .animation(.easeInOut(duration: 0.18), value: rail)
        }
        .frame(minWidth: 520, minHeight: 560)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    collapsed.toggle()
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .help(collapsed ? "Show sidebar" : "Collapse sidebar to icons")
                .accessibilityLabel(collapsed ? "Show sidebar" : "Collapse sidebar")
            }
        }
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    }

    @ViewBuilder
    private var detail: some View {
        switch app.page {
        case .dictation: DictationPage(app: app)
        case .styles: StylesPage(app: app)
        case .writing: WritingPage(app: app)
        case .notes: NotesPage(app: app, notes: app.notes)
        case .vault: VaultPage(vault: app.vault, sync: app.sync)
        case .settings: SettingsView(app: app, embedded: true)
        }
    }
}

/// The translucent sidebar background macOS uses for source lists.
private struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

private struct Sidebar: View {
    @Bindable var app: AppModel
    let rail: Bool

    private let mainPages: [Page] = [.dictation, .styles, .writing, .notes]
    private let setupPages: [Page] = [.vault, .settings]

    var body: some View {
        VStack(alignment: rail ? .center : .leading, spacing: 2) {
            header
                .padding(.top, 40) // clear of the traffic lights and the sidebar button
                .padding(.bottom, 12)
            ForEach(mainPages) { row($0) }
            Spacer().frame(height: 14)
            ForEach(setupPages) { row($0) }
            Spacer()
            footer
        }
        .padding(.horizontal, rail ? 8 : 10)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: rail ? .top : .topLeading)
    }

    private var header: some View {
        HStack(spacing: 10) {
            // From the bundle directly: the system's cached app icon can be a stale placeholder.
            Image(nsImage: Bundle.main.image(forResource: "AppIcon") ?? NSApp.applicationIconImage)
                .resizable()
                .frame(width: rail ? 32 : 34, height: rail ? 32 : 34)
            if !rail {
                Text("Audio Pencil")
                    .font(.system(size: 18, weight: .semibold, design: .serif))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.horizontal, rail ? 0 : 6)
    }

    @ViewBuilder
    private var footer: some View {
        if rail {
            Image(systemName: "lock.fill")
                .foregroundStyle(.secondary)
                .help("Private, on-device")
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Label("Private, on-device", systemImage: "lock.fill").foregroundStyle(.secondary)
                Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")")
                    .foregroundStyle(.tertiary)
            }
            .font(.caption)
            .padding(.horizontal, 6)
        }
    }

    private func row(_ page: Page) -> some View {
        let selected = app.page == page
        return Button {
            app.page = page
        } label: {
            Group {
                if rail {
                    Image(systemName: page.symbol)
                        .font(.system(size: 16))
                        .frame(width: 40, height: 34)
                        .overlay(alignment: .topTrailing) { railBadge(page) }
                } else {
                    HStack {
                        Label(page.title, systemImage: page.symbol)
                        Spacer()
                        badge(page)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 30)
                }
            }
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(selected ? Color.pencil : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled() // the filled highlight already shows the selection
        .help(rail ? page.title : "")
        .accessibilityLabel(page.title) // the rail shows only the icon
        .accessibilityValue(attentionDescription(page) ?? "")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// What the badge or rail dot says, in words, for VoiceOver.
    private func attentionDescription(_ page: Page) -> String? {
        switch page {
        case .notes where !app.notes.pending.isEmpty: "\(app.notes.pending.count) waiting for review"
        case .vault where !app.vault.settings.isConfigured: "Not set up"
        case .settings where app.needsSetup: "Permissions need attention"
        default: nil
        }
    }

    @ViewBuilder
    private func badge(_ page: Page) -> some View {
        if page == .notes, !app.notes.pending.isEmpty {
            Text("\(app.notes.pending.count)").font(.caption2.weight(.bold)).padding(.horizontal, 6).padding(.vertical, 1)
                .background(Capsule().fill(app.page == page ? Color.white.opacity(0.3) : Color.pencil))
                .foregroundStyle(app.page == page ? Color.white : Color.black.opacity(0.8))
        } else if page == .vault, !app.vault.settings.isConfigured {
            Text("Set up").font(.caption2.weight(.medium)).foregroundStyle(.secondary)
        } else if page == .settings, app.needsSetup {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
        }
    }

    /// Rails have no room for text: a dot says something needs attention.
    @ViewBuilder
    private func railBadge(_ page: Page) -> some View {
        let needsAttention = (page == .notes && !app.notes.pending.isEmpty)
            || (page == .vault && !app.vault.settings.isConfigured)
            || (page == .settings && app.needsSetup)
        if needsAttention {
            Circle()
                .fill(page == .settings ? Color.orange : Color.pencil)
                .frame(width: 8, height: 8)
                .offset(x: -3, y: 3)
        }
    }
}
