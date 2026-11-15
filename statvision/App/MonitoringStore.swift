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
    @Published private(set) var closingApplications = Set<String>()
    @Published private(set) var terminationMessage: String?
    @Published var applicationsExpanded: Bool {
        didSet {
            guard applicationsExpanded != oldValue else { return }
            defaults.set(applicationsExpanded, forKey: "applicationsExpanded")
            updateApplicationSession()
        }
    }
    @Published var menuBarVisibility: MenuBarVisibility {
        didSet {
            defaults.set(menuBarVisibility.showCPU, forKey: "menuBarShowCPU")
            defaults.set(menuBarVisibility.showMemory, forKey: "menuBarShowMemory")
            defaults.set(menuBarVisibility.showTemperature, forKey: "menuBarShowTemperature")
        }
    }
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
    private var isPanelOpen = false
    private let terminator = ApplicationTerminator()
    private var terminationChecks: [String: Task<Void, Never>] = [:]

    func terminationDisabledReason(for usage: ApplicationUsage) -> String? {
        if closingApplications.contains(usage.id) { return "Kapatma isteği gönderildi; uygulama bekleniyor." }
        return terminator.disabledReason(for: usage)
    }

    func closeApplication(_ usage: ApplicationUsage) {
        guard terminationDisabledReason(for: usage) == nil else { return }
        let outcome = terminator.requestTermination(of: usage)
        guard !outcome.targets.isEmpty else {
            terminationMessage = "\(usage.name) kapatılamadı. Uygulama değişmiş veya isteği reddetmiş olabilir."
            return
        }
        closingApplications.insert(usage.id)
        terminationMessage = outcome.rejectedCount == 0
            ? "\(usage.name) için kapatma isteği gönderildi."
            : "\(usage.name): bazı uygulama örnekleri kapatılamadı."
        // A successful send is not proof of exit: the app can show a save
        // dialog, cancel quitting, or remain unresponsive. Check once later.
        terminationChecks[usage.id] = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 8_000_000_000) } catch { return }
            guard let self else { return }
            self.closingApplications.remove(usage.id)
            self.terminationChecks[usage.id] = nil
            if outcome.targets.allSatisfy(\.isTerminated), outcome.rejectedCount == 0 {
                self.terminationMessage = "\(usage.name) kapatıldı."
            } else {
                self.terminationMessage = "\(usage.name) hâlâ açık olabilir. Kaydetme uyarısı için uygulamanın penceresini kontrol edin."
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        applicationsExpanded = defaults.object(forKey: "applicationsExpanded") as? Bool ?? false
        menuBarVisibility = MenuBarVisibility(
            showCPU: defaults.object(forKey: "menuBarShowCPU") as? Bool ?? true,
            showMemory: defaults.object(forKey: "menuBarShowMemory") as? Bool ?? true,
            showTemperature: defaults.object(forKey: "menuBarShowTemperature") as? Bool ?? true)
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
        guard isPanelOpen != open else { return }
        isPanelOpen = open
        updateApplicationSession()
    }

    private func updateApplicationSession() {
        let shouldSample = isPanelOpen && applicationsExpanded
        guard shouldSample != (applicationSession != nil) else { return }
        applicationSession = shouldSample ? UUID() : nil
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
    func stop() {
        sampler.stop()
        terminationChecks.values.forEach { $0.cancel() }
        terminationChecks.removeAll()
    }

    var cpuText: String {
        guard let percentage = latest?.cpu.percentage else { return "—" }
        return percentage.formatted(.number.precision(.fractionLength(0))) + "%"
    }
    var memoryText: String {
        guard let memory = latest?.memory else { return "—" }
        return memory.usedGB.formatted(.number.precision(.fractionLength(1))) + " GB"
    }
}

