import Foundation
import os

public enum Log {
    public static let subsystem = "com.weshopkins.audiopencil"

    public static let dictation = Logger(subsystem: subsystem, category: "dictation")
    public static let hotkey = Logger(subsystem: subsystem, category: "hotkey")
    public static let audio = Logger(subsystem: subsystem, category: "audio")
    public static let models = Logger(subsystem: subsystem, category: "models")
    public static let transcription = Logger(subsystem: subsystem, category: "transcription")
}

public enum MemoryFootprint {
    /// Physical footprint of this process in bytes: the number Activity Monitor shows as "Memory".
    public static func currentBytes() -> UInt64? {
        var usage = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0)
            }
        }
        return result == 0 ? usage.ri_phys_footprint : nil
    }

    public static func formatted(_ bytes: UInt64?) -> String {
        guard let bytes else { return "–" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }
}
