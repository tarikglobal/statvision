import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let store = MonitoringStore()
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var settingsWindow: NSWindow?
    private var subscriptions = Set<AnyCancellable>()
    private var workspaceObservers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        if let button = item.button {
            button.target = self
            button.action = #selector(togglePanel)
            button.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            button.setAccessibilityLabel("statvision sistem monitörü")
            button.setAccessibilityHelp("CPU, RAM ve sıcaklık ayrıntılarını açar. Escape paneli kapatır.")
        }
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        popover.contentSize = NSSize(width: 336, height: 472)

        store.$latest.sink { [weak self] sample in self?.updateStatus(sample) }
            .store(in: &subscriptions)
        store.$appearance.sink { [weak self] preference in
            let appearance: NSAppearance?
            switch preference {
            case .system: appearance = nil
            case .light: appearance = NSAppearance(named: .aqua)
            case .dark: appearance = NSAppearance(named: .darkAqua)
            }
            self?.popover.appearance = appearance
            self?.settingsWindow?.appearance = appearance
        }.store(in: &subscriptions)

        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.willSleepNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.popover.performClose(nil); self?.store.sleep() }
            })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.store.wake() }
            })
        store.start()
        // Finder launches should produce an immediately visible result.
        DispatchQueue.main.async { [weak self] in self?.showPanel() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return false
    }

    private func updateStatus(_ sample: SystemSample?) {
        let cpu = sample?.cpu.percentage.map {
            $0.formatted(.number.precision(.fractionLength(0))) + "%"
        } ?? "—"
        let ram = sample?.memory.map {
            $0.usedGB.formatted(.number.precision(.fractionLength(1))) + " GB"
        } ?? "—"
        let temperature = sample?.temperature?.text ?? "— °C"
        statusItem?.button?.title = "CPU \(cpu)  RAM \(ram)  \(temperature)"
        statusItem?.button?.setAccessibilityValue("CPU \(cpu), kullanılan RAM \(ram), sıcaklık \(temperature)")
        let source = sample?.temperature.map { "\($0.source.title) · \($0.sensorName)" }
            ?? "Sıcaklık sensörü kullanılamıyor"
        statusItem?.button?.toolTip = "statvision · CPU \(cpu) · RAM \(ram) · \(temperature)\n\(source)"
    }

    @objc private func togglePanel() {
        if popover.isShown { popover.performClose(nil); return }
        showPanel()
    }

    private func showPanel() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            NSApp.activate(ignoringOtherApps: true)
            popover.contentViewController?.view.window?.makeKey()
            return
        }
        // Create the chart views only while open. The sampling timer keeps running.
        store.setPanelOpen(true)
        let controller = NSHostingController(rootView:
            MonitorPanel(store: store, openSettings: { [weak self] in self?.showSettings() },
                         closePanel: { [weak self] in self?.popover.performClose(nil) }))
        controller.sizingOptions = [.preferredContentSize]
        popover.contentViewController = controller
        popover.contentSize = controller.view.fittingSize
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()
    }

    func popoverDidClose(_ notification: Notification) {
        store.setPanelOpen(false)
        // Releasing the hosting controller guarantees no hidden chart rendering.
        popover.contentViewController = nil
    }

    private func showSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 410, height: 310),
                styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "statvision Ayarları"
            window.isReleasedWhenClosed = false
            let controller = NSHostingController(rootView: SettingsView(store: store))
            controller.sizingOptions = [.preferredContentSize]
            window.contentViewController = controller
            window.setContentSize(controller.view.fittingSize)
            window.appearance = popover.appearance
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stop()
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers.removeAll()
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
    }
}

