//
//  MemoryDebugLogger.swift
//  Spot
//
//  Debug-only memory snapshots for the map redesign acceptance criteria.
//  Production builds compile out everything except a no-op `snapshot(_:)`
//  call site, so we never ship noisy memory logs to end users.
//
//  Usage:
//
//      MemoryDebugLogger.snapshot("map_appear")
//      MemoryDebugLogger.snapshot("after_first_load", extra: [
//          "annotations": map.annotations.count
//      ])
//

import Foundation

#if DEBUG
import Darwin
#endif

enum MemoryDebugLogger {

    /// Capture a memory snapshot tagged with `tag`. In RELEASE this is a
    /// no-op so production users never pay the cost. In DEBUG this reads the
    /// process resident size via `task_info` and emits a `MapView`-tagged
    /// log entry compatible with the existing structured logger.
    static func snapshot(_ tag: String, extra: [String: Any] = [:]) {
        #if DEBUG
        var details: [String: Any] = ["tag": tag]
        if let bytes = residentBytes() {
            let mb = Double(bytes) / 1_048_576.0
            details["residentMB"] = String(format: "%.1f", mb)
            details["residentBytes"] = bytes
        }
        for (k, v) in extra { details[k] = v }
        SpotLogger.log(MapViewLogs.memorySnapshot, details: details)
        #else
        _ = tag
        _ = extra
        #endif
    }

    #if DEBUG
    /// Reads the resident memory footprint (in bytes) of the current process.
    /// Returns `nil` if the syscall fails — we silently degrade rather than
    /// spamming errors, since this is a developer-only signal.
    private static func residentBytes() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info>.size / MemoryLayout<integer_t>.size)
        let kerr = withUnsafeMutablePointer(to: &info) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard kerr == KERN_SUCCESS else { return nil }
        return info.phys_footprint
    }
    #endif
}
