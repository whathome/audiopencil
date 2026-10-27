import AppKit
import SwiftUI
import Testing

@MainActor struct CallApplicationPickerTests {
    private let applications = [
        CallApplication(id: 10, name: "Browser", bundleID: "test.browser"),
        CallApplication(id: 20, name: "Browser", bundleID: "test.browser.second"),
    ]

    private func button() -> NSPopUpButton {
        _ = NSApplication.shared
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.menu?.autoenablesItems = false
        return button
    }

    @Test func everyNativeMenuPresentationRefreshesApplications() {
        var refreshes = 0
        let picker = CallApplicationPicker(applications: [], selection: .constant(nil), isLoading: false) {
            refreshes += 1
        }
        let coordinator = picker.makeCoordinator()
        let menu = NSMenu()
        coordinator.menuWillOpen(menu)
        #expect(refreshes == 1)
        coordinator.menuWillOpen(menu)
        #expect(refreshes == 2)
    }

    @Test func applicationsWithTheSameNameRemainDistinctAndSelectable() {
        var selection: Int32?
        let picker = CallApplicationPicker(
            applications: applications, selection: Binding(get: { selection }, set: { selection = $0 }),
            isLoading: false, refresh: {}
        )
        let coordinator = picker.makeCoordinator()
        let button = button()
        coordinator.update(picker, button: button)
        #expect(button.numberOfItems == 3)
        button.selectItem(at: 2)
        coordinator.selectApplication(button)
        #expect(selection == 20)
        button.selectItem(at: 0)
        coordinator.selectApplication(button)
        #expect(selection == nil)
    }

    @Test func refreshPreservesTheSelectedProcessAndDisablesItsLoadingMessage() {
        let picker = CallApplicationPicker(applications: applications, selection: .constant(20), isLoading: false, refresh: {})
        let coordinator = picker.makeCoordinator()
        let button = button()
        coordinator.update(picker, button: button)
        let refreshing = CallApplicationPicker(
            applications: Array(applications.reversed()), selection: .constant(20), isLoading: true, refresh: {}
        )
        coordinator.update(refreshing, button: button)
        #expect((button.selectedItem?.representedObject as? NSNumber)?.int32Value == 20)
        #expect(button.itemArray.last?.isEnabled == false)
    }

    @Test func emptyAndStaleSelectionsShowThePlaceholder() {
        let picker = CallApplicationPicker(applications: [], selection: .constant(20), isLoading: false, refresh: {})
        let coordinator = picker.makeCoordinator()
        let button = button()
        coordinator.update(picker, button: button)
        #expect(button.indexOfSelectedItem == 0)
        #expect(button.itemArray.last?.isEnabled == false)
    }
}
