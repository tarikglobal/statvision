import AppKit
import Darwin

/// Quits observed application instances through AppKit. Never sends Unix
/// signals, targets arbitrary PIDs, or automatically escalates to force quit.
@MainActor
final class ApplicationTerminator {
    struct Outcome {
        let targets: [NSRunningApplication]
        let rejectedCount: Int
    }

    func disabledReason(for usage: ApplicationUsage) -> String? {
        let targets = runningTargets(for: usage)
        guard !targets.isEmpty else { return "Ana uygulama artık çalışmıyor veya liste yenileniyor." }
        return targets.compactMap { reason(for: $0) }.first
    }

    func requestTermination(of usage: ApplicationUsage) -> Outcome {
        let targets = runningTargets(for: usage)
        guard !targets.isEmpty, targets.allSatisfy({ reason(for: $0) == nil }) else {
            return Outcome(targets: [], rejectedCount: max(1, targets.count))
        }
        var accepted: [NSRunningApplication] = []
        var rejected = 0
        for app in targets {
            // Check the process birth time immediately before the request. A
            // relaunched app reusing the same PID is not the observed instance.
            guard ApplicationTerminationPolicy.matchesObservedProcess(identity(for: app), observed: usage.processes),
                  !app.isTerminated, app.terminate() else {
                rejected += 1
                continue
            }
            accepted.append(app)
        }
        return Outcome(targets: accepted, rejectedCount: rejected)
    }

    private func runningTargets(for usage: ApplicationUsage) -> [NSRunningApplication] {
        let observedPIDs = Set(usage.processes.map(\.pid))
        return NSWorkspace.shared.runningApplications.filter {
            !$0.isTerminated && $0.bundleURL?.path == usage.id && observedPIDs.contains($0.processIdentifier)
        }
    }

    private func reason(for app: NSRunningApplication) -> String? {
        ApplicationTerminationPolicy.disabledReason(bundleIdentifier: app.bundleIdentifier,
            bundlePath: app.bundleURL?.path ?? "",
            isOwnApplication: app == NSRunningApplication.current
                || app.bundleIdentifier == Bundle.main.bundleIdentifier,
            isProhibited: app.activationPolicy == .prohibited)
    }

    private func identity(for app: NSRunningApplication) -> ProcessIdentity? {
        var usage = rusage_info_v2()
        let status = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(app.processIdentifier, RUSAGE_INFO_V2, $0)
            }
        }
        guard status == 0, usage.ri_proc_exit_abstime == 0 else { return nil }
        return ProcessIdentity(pid: app.processIdentifier, startTime: usage.ri_proc_start_abstime)
    }
}
