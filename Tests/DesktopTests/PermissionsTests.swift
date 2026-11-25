import Foundation
import ScreenCaptureKit
import Testing

@MainActor struct PermissionsTests {
    @Test func grantedAccessDoesNotRequestAgainOrOpenSettings() async {
        var requests = 0
        var settingsOpened = false
        let permissions = Permissions(
            screenCaptureAccess: { true },
            requestScreenCaptureAccess: { requests += 1 },
            openScreenCaptureSettings: { settingsOpened = true }
        )

        await permissions.requestOnlineMeetingAudio()

        #expect(permissions.onlineMeetingAudio)
        #expect(requests == 0)
        #expect(!settingsOpened)
        #expect(!permissions.requestingOnlineMeetingAudio)
    }

    @Test func successfulGrantRefreshesAccessWithoutOpeningSettings() async {
        var granted = false
        var settingsOpened = false
        let permissions = Permissions(
            screenCaptureAccess: { granted },
            requestScreenCaptureAccess: { granted = true },
            openScreenCaptureSettings: { settingsOpened = true }
        )

        await permissions.requestOnlineMeetingAudio()

        #expect(permissions.onlineMeetingAudio)
        #expect(permissions.onlineMeetingAudioRequestError == nil)
        #expect(!settingsOpened)
        #expect(!permissions.requestingOnlineMeetingAudio)
    }

    @Test func deniedRequestFinishesBeforeOpeningSettings() async {
        var events: [String] = []
        let permissions = Permissions(
            screenCaptureAccess: { false },
            requestScreenCaptureAccess: {
                events.append("request")
                throw NSError(domain: SCStreamErrorDomain, code: SCStreamError.Code.userDeclined.rawValue)
            },
            openScreenCaptureSettings: { events.append("settings") }
        )

        await permissions.requestOnlineMeetingAudio()

        #expect(events == ["request", "settings"])
        #expect(!permissions.onlineMeetingAudio)
        #expect(permissions.onlineMeetingAudioRequestError == nil)
        #expect(!permissions.requestingOnlineMeetingAudio)
    }

    @Test func requestCompletionAloneDoesNotClaimAccess() async {
        var settingsOpened = false
        let permissions = Permissions(
            screenCaptureAccess: { false },
            requestScreenCaptureAccess: {},
            openScreenCaptureSettings: { settingsOpened = true }
        )

        await permissions.requestOnlineMeetingAudio()

        #expect(!permissions.onlineMeetingAudio)
        #expect(settingsOpened)
    }

    @Test func unexpectedFailureIsVisibleAndStillOffersSettings() async {
        var granted = false
        var settingsOpened = false
        let permissions = Permissions(
            screenCaptureAccess: { granted },
            requestScreenCaptureAccess: {
                throw NSError(domain: "PermissionTest", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "ScreenCaptureKit unavailable"])
            },
            openScreenCaptureSettings: { settingsOpened = true }
        )

        await permissions.requestOnlineMeetingAudio()

        #expect(permissions.onlineMeetingAudioRequestError?.contains("ScreenCaptureKit unavailable") == true)
        #expect(!permissions.onlineMeetingAudio)
        #expect(settingsOpened)
        #expect(!permissions.requestingOnlineMeetingAudio)

        granted = true
        permissions.refresh()
        #expect(permissions.onlineMeetingAudio)
        #expect(permissions.onlineMeetingAudioRequestError == nil)
    }

    @Test func repeatedClicksDoNotStartConcurrentRequests() async throws {
        var started: CheckedContinuation<Void, Never>?
        var finish: CheckedContinuation<Void, Never>?
        var requests = 0
        var settingsOpened = false
        let permissions = Permissions(
            screenCaptureAccess: { false },
            requestScreenCaptureAccess: {
                requests += 1
                started?.resume()
                await withCheckedContinuation { finish = $0 }
            },
            openScreenCaptureSettings: { settingsOpened = true }
        )

        let first = Task { await permissions.requestOnlineMeetingAudio() }
        await withCheckedContinuation { started = $0 }
        #expect(permissions.requestingOnlineMeetingAudio)

        await permissions.requestOnlineMeetingAudio()
        #expect(requests == 1)
        #expect(!settingsOpened)

        let completion = try #require(finish)
        completion.resume()
        await first.value
        #expect(!permissions.requestingOnlineMeetingAudio)
        #expect(settingsOpened)
    }
}
