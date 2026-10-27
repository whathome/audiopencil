import AppKit
import SwiftUI

/// Refresh on native menu presentation, including keyboard and accessibility activation.
struct CallApplicationPicker: NSViewRepresentable {
    let applications: [CallApplication]
    @Binding var selection: Int32?
    let isLoading: Bool
    let refresh: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.target = context.coordinator
        button.action = #selector(Coordinator.selectApplication(_:))
        button.menu?.delegate = context.coordinator
        button.menu?.autoenablesItems = false
        button.setAccessibilityLabel(String(localized: "Call app"))
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        button.isEnabled = context.environment.isEnabled
        context.coordinator.update(self, button: button)
    }

    static func dismantleNSView(_ button: NSPopUpButton, coordinator: Coordinator) {
        button.menu?.cancelTrackingWithoutAnimation()
        button.menu?.delegate = nil
        button.target = nil
    }

    final class Coordinator: NSObject, NSMenuDelegate {
        private var picker: CallApplicationPicker
        private var displayedApplications: [CallApplication]?
        private var displayedLoading = false

        init(_ picker: CallApplicationPicker) { self.picker = picker }

        func update(_ picker: CallApplicationPicker, button: NSPopUpButton) {
            self.picker = picker
            if displayedApplications != picker.applications || displayedLoading != picker.isLoading {
                displayedApplications = picker.applications
                displayedLoading = picker.isLoading
                button.removeAllItems()
                button.addItem(withTitle: String(localized: "Choose a running app"))
                for application in picker.applications {
                    let item = NSMenuItem(title: application.name, action: nil, keyEquivalent: "")
                    item.representedObject = NSNumber(value: application.id)
                    button.menu?.addItem(item)
                }
                if picker.isLoading || picker.applications.isEmpty {
                    let item = NSMenuItem(
                        title: picker.isLoading ? String(localized: "Refreshing apps…") : String(localized: "No running apps found"),
                        action: nil, keyEquivalent: ""
                    )
                    item.isEnabled = false
                    button.menu?.addItem(item)
                }
            }
            let selected = button.itemArray.first {
                ($0.representedObject as? NSNumber)?.int32Value == picker.selection && $0.isEnabled
            }
            button.select(selected ?? button.itemArray.first)
        }

        func menuWillOpen(_ menu: NSMenu) { picker.refresh() }

        @objc func selectApplication(_ sender: NSPopUpButton) {
            picker.selection = (sender.selectedItem?.representedObject as? NSNumber)?.int32Value
        }
    }
}
