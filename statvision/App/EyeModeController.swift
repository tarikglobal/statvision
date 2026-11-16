import AppKit
import Combine
import SwiftUI

/// Uses local tracking areas only: no event tap, input monitoring or polling.
@MainActor
final class EyeModeController {
    private weak var button: NSStatusBarButton?
    private let store: MonitoringStore
    private var state = EyeInteractionState()
    private let images = Dictionary(uniqueKeysWithValues: EyeLoadLevel.allCases.map { load in
        (load, [1.0, 0.28, 0.025].map { EyeArtwork.statusImage(openness: $0, load: load) })
    })
    private var load = EyeLoadLevel.unavailable
    private var phase = 0
    private var blinkInterval = EyeBlinkTiming.defaultSeconds
    private var timingSubscription: AnyCancellable?
    private var blinkTimer: DispatchSourceTimer?
    private var blinkTask: Task<Void, Never>?
    private var showTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    private var statusTracker: EyeHoverTracker?
    private var previewTracker: EyeHoverTracker?
    private var panel: EyePreviewPanel?
    private var accessibilityObserver: NSObjectProtocol?

    var currentImage: NSImage { images[load]![phase] }

    init(button: NSStatusBarButton, store: MonitoringStore) {
        self.button = button
        self.store = store
        state.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        statusTracker = EyeHoverTracker(view: button) { [weak self] inside in
            guard let self else { return }
            self.state.statusHovered = inside
            self.refresh()
        }
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.state.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                    self.refresh()
                }
            }
        timingSubscription = store.$eyeBlinkInterval.removeDuplicates().sink { [weak self] seconds in
            self?.setBlinkInterval(seconds)
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard state.enabled != enabled else { return }
        state.enabled = enabled
        refresh()
    }

    func updateLoad(_ cpu: CPUReading?) {
        let next = EyeLoadLevel(cpu: cpu)
        guard load != next else { return }
        load = next
        if state.enabled { button?.image = currentImage }
    }

    func setMainPanelOpen(_ open: Bool) {
        state.mainPanelOpen = open
        refresh()
    }

    func setSleeping(_ sleeping: Bool) {
        state.sleeping = sleeping
        if sleeping { state.statusHovered = false; state.previewHovered = false }
        refresh()
    }

    func applyAppearance(_ appearance: NSAppearance?) { panel?.appearance = appearance }

    private func setBlinkInterval(_ seconds: Int) {
        let interval = EyeBlinkTiming.validated(seconds)
        guard blinkInterval != interval else { return }
        blinkInterval = interval
        stopBlinking()
        refresh()
    }

    private func refresh() {
        if state.shouldBlink { startBlinking() } else { stopBlinking() }
        if state.shouldShowPreview {
            hideTask?.cancel()
            hideTask = nil
            guard panel?.isVisible != true, showTask == nil else { return }
            showTask = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: 180_000_000) } catch { return }
                guard let self else { return }
                self.showTask = nil
                if self.state.shouldShowPreview { self.showPreview() }
            }
        } else {
            showTask?.cancel()
            showTask = nil
            if !state.enabled || state.sleeping || state.mainPanelOpen {
                hideTask?.cancel()
                hideTask = nil
                hidePreview()
            } else if panel?.isVisible == true {
                hideTask?.cancel()
                hideTask = Task { [weak self] in
                    do { try await Task.sleep(nanoseconds: 240_000_000) } catch { return }
                    guard let self else { return }
                    self.hideTask = nil
                    if !self.state.shouldShowPreview { self.hidePreview() }
                }
            }
        }
    }

    private func startBlinking() {
        guard blinkTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + Double(blinkInterval), repeating: Double(blinkInterval),
                       leeway: .milliseconds(200))
        timer.setEventHandler { [weak self] in self?.blink() }
        blinkTimer = timer
        timer.resume()
    }

    private func blink() {
        guard state.shouldBlink else { return }
        blinkTask?.cancel()
        blinkTask = Task { [weak self] in
            for (image, delay) in [(1, UInt64(55_000_000)), (2, 80_000_000), (1, 55_000_000), (0, 0)] {
                guard let self, !Task.isCancelled, self.state.shouldBlink else { return }
                self.phase = image
                self.button?.image = self.currentImage
                if delay > 0 {
                    do { try await Task.sleep(nanoseconds: delay) } catch { return }
                }
            }
        }
    }

    private func stopBlinking() {
        blinkTimer?.cancel()
        blinkTimer = nil
        blinkTask?.cancel()
        blinkTask = nil
        if phase != 0 {
            phase = 0
            if state.enabled { button?.image = currentImage }
        }
    }

    private func showPreview() {
        guard let button, let window = button.window, let screen = window.screen ?? NSScreen.main else { return }
        let panel = self.panel ?? EyePreviewPanel(contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        switch store.appearance {
        case .system: panel.appearance = nil
        case .dark: panel.appearance = NSAppearance(named: .darkAqua)
        case .light: panel.appearance = NSAppearance(named: .aqua)
        }
        let view = NSHostingView(rootView: HoverPreview(store: store))
        let size = view.fittingSize
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        let area = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        let x = max(area.minX, min(anchor.midX - size.width / 2, area.maxX - size.width))
        let y = max(area.minY, min(anchor.minY - size.height - 7, area.maxY - size.height))
        panel.contentView = view
        panel.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: size), display: false)
        previewTracker?.stop()
        previewTracker = EyeHoverTracker(view: view) { [weak self] inside in
            guard let self else { return }
            self.state.previewHovered = inside
            self.refresh()
        }
        self.panel = panel
        // Never make this panel key or activate statvision on hover.
        panel.orderFrontRegardless()
    }

    private func hidePreview() {
        previewTracker?.stop()
        previewTracker = nil
        panel?.orderOut(nil)
        panel?.contentView = nil
        state.previewHovered = false
    }

    func stop() {
        state.enabled = false
        timingSubscription?.cancel()
        timingSubscription = nil
        stopBlinking()
        showTask?.cancel()
        hideTask?.cancel()
        hidePreview()
        statusTracker?.stop()
        statusTracker = nil
        if let accessibilityObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver)
            self.accessibilityObserver = nil
        }
    }
}

@MainActor
final class EyePreviewPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class EyeHoverTracker: NSObject {
    private weak var view: NSView?
    private var area: NSTrackingArea?
    private let changed: (Bool) -> Void

    init(view: NSView, changed: @escaping (Bool) -> Void) {
        self.view = view
        self.changed = changed
        super.init()
        let area = NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        self.area = area
        view.addTrackingArea(area)
    }

    @objc(mouseEntered:) private func entered(_ event: NSEvent) { changed(true) }
    @objc(mouseExited:) private func exited(_ event: NSEvent) { changed(false) }

    func stop() {
        if let area { view?.removeTrackingArea(area) }
        area = nil
    }
}
