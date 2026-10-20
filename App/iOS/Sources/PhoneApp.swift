import SwiftUI
import UIKit

@main
struct PhoneApp: App {
    @State private var app = PhoneModel()

    init() {
        // Titles in New York, like the Mac app: the serif is for the written word and the page's name.
        let appearance = UINavigationBar.appearance()
        if let large = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .largeTitle).withDesign(.serif)?.withSymbolicTraits(.traitBold) {
            appearance.largeTitleTextAttributes = [.font: UIFont(descriptor: large, size: 0)]
        }
        if let inline = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .headline).withDesign(.serif) {
            appearance.titleTextAttributes = [.font: UIFont(descriptor: inline, size: 0)]
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(app: app)
                .tint(Color.pencil)
                .task { app.bootstrap() }
        }
    }
}

struct RootView: View {
    @Bindable var app: PhoneModel
    @State private var tab = Tab.record

    enum Tab: Hashable {
        case record, notes, settings
    }

    var body: some View {
        @Bindable var notes = app.notes
        TabView(selection: $tab) {
            SwiftUI.Tab("Record", systemImage: "mic", value: Tab.record) {
                RecordView(app: app)
            }
            SwiftUI.Tab("Notes", systemImage: "doc.text", value: Tab.notes) {
                NotesView(app: app)
            }
            .badge(app.notes.pending.count)
            SwiftUI.Tab("Settings", systemImage: "gearshape", value: Tab.settings) {
                PhoneSettingsView(app: app)
            }
        }
        .sheet(item: $notes.reviewing) { item in
            NavigationStack {
                ReviewView(item: item, knownTags: app.tags) { title, tags, folder in
                    app.notes.approve(item, title: title, tags: tags, folder: folder)
                } skip: {
                    app.notes.skip(item)
                }
                .navigationTitle("Review note")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Later") { app.notes.reviewing = nil }
                    }
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Discard", role: .destructive) { app.notes.discard(item) }
                    }
                }
            }
            .interactiveDismissDisabled()
            .tint(Color.pencil)
        }
        .fullScreenCover(isPresented: Binding(get: { !app.setupCompleted }, set: { _ in })) {
            PhoneSetupView(app: app)
                .tint(Color.pencil) // presented views don't pick up the app's accent on their own
        }
    }
}
