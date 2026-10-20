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
        #if os(macOS)
        var usage = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0)
            }
        }
        return result == 0 ? usage.ri_phys_footprint : nil
        #else
        // The number iOS's memory limit is judged on.
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : nil
        #endif
    }

    public static func formatted(_ bytes: UInt64?) -> String {
        guard let bytes else { return "–" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }
}
