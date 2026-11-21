// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Darwin

/// What a program takes of the processor, in cores: 1 is one core busy all the time, the sum of all its threads.
public enum EngineLoad {
    /// The share of the machine: the cores in use over the cores there are (what Activity Monitor calls the total load).
    public static func machineShare(cores: Double, coreCount: Int = ProcessInfo.processInfo.activeProcessorCount) -> Double {
        coreCount > 0 ? cores / Double(coreCount) : 0
    }

    /// The cores used over a period, from the processor time the program took and the time that went by.
    public static func cores(cpuSeconds: Double, wallSeconds: Double) -> Double {
        wallSeconds > 0 ? max(0, cpuSeconds / wallSeconds) : 0
    }
}

/// Reads the processor time a process has used, to work out its load between two readings.
public struct EngineLoadSampler {
    public let pid: pid_t
    private var last: (cpu: Double, wall: Double)?

    public init(pid: pid_t) { self.pid = pid }

    /// The processor time used so far by the process and its threads, in seconds; nil if the process cannot be read.
    public static func cpuSeconds(of pid: pid_t) -> Double? {
        var info = rusage_info_v4()
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
        }
        guard status == 0 else { return nil }
        var base = mach_timebase_info_data_t()
        mach_timebase_info(&base)
        let ticks = Double(info.ri_user_time + info.ri_system_time)
        return ticks * Double(base.numer) / Double(base.denom) / 1_000_000_000
    }

    /// The cores used since the previous reading (the first reading has no period: nil).
    public mutating func sample() -> Double? {
        guard let cpu = Self.cpuSeconds(of: pid) else { return nil }
        let wall = Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
        defer { last = (cpu, wall) }
        guard let last else { return nil }
        return EngineLoad.cores(cpuSeconds: cpu - last.cpu, wallSeconds: wall - last.wall)
    }
}
