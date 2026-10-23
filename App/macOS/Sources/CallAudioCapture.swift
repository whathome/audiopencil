import APAudio
import AppKit
import AVFoundation
import CoreMedia
import ScreenCaptureKit
import os

struct CallApplication: Identifiable, Hashable {
    let id: Int32
    let name: String
    let bundleID: String
}

/// ScreenCaptureKit's audio output only. No screen output or image is installed or retained.
nonisolated final class CallAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    #if DEBUG
    static let isAvailable = true
    #else
    static let isAvailable = false
    #endif

    private var stream: SCStream?
    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?
    private let queue = DispatchQueue(label: "com.weshopkins.audiopencil.call-audio", qos: .userInitiated)
    private let onSamples: @Sendable ([Float], Double) -> Void
    private let onFailure: @Sendable (String) -> Void
    private let active = OSAllocatedUnfairLock(initialState: true)
    private let streamEnded = OSAllocatedUnfairLock(initialState: false)

    init(onSamples: @escaping @Sendable ([Float], Double) -> Void, onFailure: @escaping @Sendable (String) -> Void) {
        self.onSamples = onSamples
        self.onFailure = onFailure
    }

    static func applications() async throws -> [CallApplication] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        let foregroundProcessIDs = await MainActor.run {
            Set(NSWorkspace.shared.runningApplications.filter {
                $0.activationPolicy == .regular && !$0.isTerminated
            }.map(\.processIdentifier))
        }
        return content.applications.filter {
            foregroundProcessIDs.contains($0.processID)
                && $0.processID != ProcessInfo.processInfo.processIdentifier
                && !$0.applicationName.isEmpty
        }.map { CallApplication(id: $0.processID, name: $0.applicationName, bundleID: $0.bundleIdentifier) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func start(applicationID: Int32) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first,
              let application = content.applications.first(where: { $0.processID == applicationID }) else {
            throw MeetingCaptureError.unavailable(String(localized: "The selected call app is no longer running. Refresh the app list and choose it again."))
        }
        let filter = SCContentFilter(display: display, including: [application], exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(seconds: 1, preferredTimescale: 1)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        self.stream = stream
        do { try await stream.startCapture() }
        catch {
            self.stream = nil
            throw error
        }
    }

    func stop() async throws {
        active.withLock { $0 = false }
        guard let stream else { return }
        if !streamEnded.withLock({ $0 }) { try await stream.stopCapture() }
        self.stream = nil
        streamEnded.withLock { $0 = true }
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        streamEnded.withLock { $0 = true }
        fail(error)
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard active.withLock({ $0 }), type == .audio, sampleBuffer.isValid, CMSampleBufferDataIsReady(sampleBuffer),
              CMSampleBufferGetNumSamples(sampleBuffer) > 0 else { return }
        do {
            guard let description = CMSampleBufferGetFormatDescription(sampleBuffer) else {
                throw MeetingCaptureError.unavailable(String(localized: "The call app supplied an unsupported audio format."))
            }
            let format = AVAudioFormat(cmAudioFormatDescription: description)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))) else {
                throw MeetingCaptureError.unavailable(String(localized: "The call app supplied an unsupported audio format."))
            }
            buffer.frameLength = buffer.frameCapacity
            let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(sampleBuffer, at: 0, frameCount: Int32(buffer.frameLength), into: buffer.mutableAudioBufferList)
            guard status == noErr else { throw AudioRecorderError.unsupportedFormat("call audio: \(status)") }
            if inputFormat != format {
                let mono = AVAudioFormat(standardFormatWithSampleRate: AudioRecorder.sampleRate, channels: 1)!
                guard let converter = AVAudioConverter(from: format, to: mono) else { throw AudioRecorderError.unsupportedFormat(format.description) }
                converter.downmix = true
                self.converter = converter
                inputFormat = format
            }
            guard let converter,
                  let output = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: AVAudioFrameCount(Double(buffer.frameLength) * AudioRecorder.sampleRate / format.sampleRate) + 256) else {
                throw AudioRecorderError.unsupportedFormat(format.description)
            }
            nonisolated(unsafe) var supplied = false
            var error: NSError?
            let result = converter.convert(to: output, error: &error) { _, state in
                if supplied { state.pointee = .noDataNow; return nil }
                supplied = true
                state.pointee = .haveData
                return buffer
            }
            if let error { throw error }
            guard result != .error, let channel = output.floatChannelData?[0] else {
                throw AudioRecorderError.unsupportedFormat(format.description)
            }
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
            guard timestamp.isFinite else { throw AudioRecorderError.unsupportedFormat("call audio timestamp") }
            onSamples(Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength))), timestamp)
        } catch {
            fail(error)
        }
    }

    private func fail(_ error: any Error) {
        let shouldReport = active.withLock { active in
            let wasActive = active
            active = false
            return wasActive
        }
        if shouldReport { onFailure(error.localizedDescription) }
    }
}
