import AppKit
import SwiftUI

/// Owns the on-screen windows, the refresh loop, and click behaviour.
@MainActor
final class NotchController: ObservableObject {
    let state = AppState()

    private var barPanel: NSPanel?
    private var dropdown: NSPanel?
    private var settingsPanel: NSPanel?
    private var openSide: Side?
    private var layout = NotchLayout.current()

    private var refreshTimer: Timer?
    private var outsideClickMonitor: Any?
    private var napAssertion: NSObjectProtocol?

    // MARK: Lifecycle

    func start() {
        // Accessory apps get App Nap'd when never frontmost, which throttles the
        // refresh timer to minutes. This keeps our polling alive while still
        // letting the Mac sleep normally when idle.
        napAssertion = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .automaticTerminationDisabled],
            reason: "Poll GitHub for PR updates")

        buildBarPanel()
        scheduleRefresh()

        // Re-fetch immediately when the Mac wakes — the timer may have been
        // suspended during sleep, so data could be stale.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshNow(reason: "wake-from-sleep") }
        }

        refreshNow(reason: "launch")
    }

    func relayout() {
        layout = NotchLayout.current()
        barPanel?.setFrame(layout.windowFrame, display: true)
        closeDropdown()
    }

    private func scheduleRefresh() {
        refreshTimer?.invalidate()
        let interval = max(20, state.settings.refreshInterval)
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.refreshNow(reason: "timer-\(Int(interval))s") }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
        NSLog("[s8notch] refresh timer scheduled every %.0fs", interval)
    }

    func refreshNow(reason: String = "manual") {
        NSLog("[s8notch] heartbeat — refresh requested (%@)", reason)
        Task { await state.refresh() }
    }

    // MARK: Bar panel

    private func buildBarPanel() {
        let panel = makePanel(frame: layout.windowFrame)
        let root = NotchBarView(layout: layout)
            .environmentObject(state)
            .environmentObject(self)
        panel.contentView = NSHostingView(rootView: root)
        panel.orderFrontRegardless()
        barPanel = panel
    }

    private func makePanel(frame: CGRect) -> NSPanel {
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        return panel
    }

    // MARK: Dropdown

    func toggleDropdown(_ side: Side) {
        if openSide == side { closeDropdown(); return }
        openDropdown(side)
    }

    private func openDropdown(_ side: Side) {
        closeDropdown()
        openSide = side
        refreshNow(reason: "open-dropdown")   // always show fresh data when the user opens a list

        let width: CGFloat = 400
        let maxHeight: CGFloat = 460
        let f = layout.screen.frame
        var x = layout.clusterCenterX(side) - width / 2
        x = min(max(x, f.minX + 8), f.maxX - width - 8)
        let y = f.maxY - layout.barHeight - maxHeight

        let panel = makePanel(frame: CGRect(x: x, y: y, width: width, height: maxHeight))
        panel.hasShadow = true
        let root = DropdownView(side: side, maxHeight: maxHeight)
            .environmentObject(state)
            .environmentObject(self)
        panel.contentView = NSHostingView(rootView: root)
        panel.orderFrontRegardless()
        dropdown = panel

        // Dismiss when the user clicks anywhere outside our windows.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in self?.closeDropdown() }
        }
    }

    func closeDropdown() {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
        dropdown?.orderOut(nil)
        dropdown = nil
        openSide = nil
    }

    // MARK: Actions

    func open(_ pr: PullRequest) {
        NSWorkspace.shared.open(pr.url)
        closeDropdown()
    }

    func openSettings() {
        closeDropdown()
        if let existing = settingsPanel {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let width: CGFloat = 340, height: CGFloat = 500
        let f = layout.screen.frame
        let frame = CGRect(x: f.midX - width / 2, y: f.midY - height / 2, width: width, height: height)
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        panel.title = "S8 Notch — Settings"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(
            rootView: SettingsView().environmentObject(state).environmentObject(self)
        )
        settingsPanel = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Re-arm the timer after the interval setting changes.
    func settingsChanged() { scheduleRefresh() }

    func quit() { NSApp.terminate(nil) }
}
