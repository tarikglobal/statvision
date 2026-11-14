import AppKit
import Combine
import SwiftUI

enum AppearancePreference: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "Sistem"
        case .light: return "Açık"
        case .dark: return "Koyu"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

@MainActor
final class MonitoringStore: ObservableObject {
    @Published private(set) var latest: SystemSample?
    @Published private(set) var history = SampleHistory()
    @Published private(set) var applicationUsage: ApplicationUsageSnapshot?
    @Published private(set) var hasApplicationSample = false
    @Published var refreshInterval: Int {
        didSet {
            guard refreshInterval != oldValue else { return }
            if ![1, 2, 5].contains(refreshInterval) { refreshInterval = 2 }
            defaults.set(refreshInterval, forKey: "refreshInterval")
            if !isSleeping { sampler.start(interval: Double(refreshInterval)) }
        }
    }
    @Published var appearance: AppearancePreference {
        didSet { defaults.set(appearance.rawValue, forKey: "appearance") }
    }
    private let defaults: UserDefaults
    private let sampler = SystemSampler()
    private var isSleeping = false
    private var applicationSession: UUID?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedInterval = defaults.integer(forKey: "refreshInterval")
        refreshInterval = [1, 2, 5].contains(storedInterval) ? storedInterval : 2
        appearance = AppearancePreference(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system
        sampler.onSample = { [weak self] sample in
            DispatchQueue.main.async {
                guard let self else { return }
                self.history.append(sample)
                self.latest = sample
            }
        }
        sampler.onApplications = { [weak self] session, snapshot in
            DispatchQueue.main.async {
                guard let self, self.applicationSession == session else { return }
                self.applicationUsage = snapshot
                self.hasApplicationSample = true
                self.updateApplicationDescriptors()
            }
        }
    }

    func setPanelOpen(_ open: Bool) {
        applicationSession = open ? UUID() : nil
        applicationUsage = nil
        hasApplicationSample = false
        updateApplicationDescriptors()
    }

    private func updateApplicationDescriptors() {
        let applications: [ApplicationDescriptor]
        if applicationSession != nil {
            applications = NSWorkspace.shared.runningApplications.compactMap { app in
                guard !app.isTerminated, app.activationPolicy != .prohibited,
                      let bundleURL = app.bundleURL else { return nil }
                return ApplicationDescriptor(pid: app.processIdentifier,
                    name: app.localizedName ?? bundleURL.deletingPathExtension().lastPathComponent,
                    bundlePath: bundleURL.path)
            }
        } else { applications = [] }
        sampler.setApplications(applications, session: applicationSession)
    }

    func start() { sampler.start(interval: Double(refreshInterval)) }
    func sleep() { isSleeping = true; sampler.pauseForSleep() }
    func wake() { isSleeping = false; sampler.start(interval: Double(refreshInterval)) }
    func stop() { sampler.stop() }

    var cpuText: String {
        guard let percentage = latest?.cpu.percentage else { return "—" }
        return percentage.formatted(.number.precision(.fractionLength(0))) + "%"
    }
    var memoryText: String {
        guard let memory = latest?.memory else { return "—" }
        return memory.usedGB.formatted(.number.precision(.fractionLength(1))) + " GB"
    }
}

