import AppKit
import Combine
import SwiftUI

/// Owns the on-screen windows, the refresh loop, and click behaviour.
@MainActor
final class NotchController: ObservableObject {
    let state = AppState()

    private var barPanel: NSPanel?
    private var statusItem: NSStatusItem?
    private var dropdown: NSPanel?
    private var settingsPanel: NSPanel?
    private var onboardingPanel: NSPanel?
    private var openSide: Side?
    private var layout = NotchLayout.current()

    private var refreshTimer: Timer?
    private var outsideClickMonitor: Any?
    private var napAssertion: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()

    // MARK: Lifecycle

    func start() {
        // Accessory apps get App Nap'd when never frontmost, which throttles the
        // refresh timer to minutes. This keeps our polling alive while still
        // letting the Mac sleep normally when idle.
        napAssertion = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .automaticTerminationDisabled],
            reason: "Poll GitHub for PR updates")

        buildPresentation()
        scheduleRefresh()

        // Re-fetch immediately when the Mac wakes — the timer may have been
        // suspended during sleep, so data could be stale.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshNow(reason: "wake-from-sleep") }
        }

        // First launch: ask which org to watch before we start surfacing PRs.
        if !state.settings.hasCompletedOnboarding {
            presentOnboarding()
        }

        refreshNow(reason: "launch")
    }

    // MARK: Onboarding

    private func presentOnboarding() {
        let width: CGFloat = 380, height: CGFloat = 250
        let f = layout.screen.frame
        let frame = CGRect(x: f.midX - width / 2, y: f.midY - height / 2, width: width, height: height)
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.titled],   // no close button — finish via Continue
            backing: .buffered, defer: false
        )
        panel.title = "Git Notch Setup"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(
            rootView: OnboardingView(onDone: { [weak self] in self?.finishOnboarding() })
                .environmentObject(state)
        )
        onboardingPanel = panel
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func finishOnboarding() {
        state.settings.hasCompletedOnboarding = true
        onboardingPanel?.orderOut(nil)
        onboardingPanel = nil
        refreshNow(reason: "onboarding-complete")   // re-fetch with the chosen org
    }

    /// Build whichever presentation suits the current display: the notch bar on
    /// a notched Mac, or a menu-bar status item (tray) on a notch-less one.
    private func buildPresentation() {
        if layout.hasNotch {
            buildBarPanel()
        } else {
            buildStatusItem()
        }
    }

    private func tearDownPresentation() {
        barPanel?.orderOut(nil)
        barPanel = nil
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
        cancellables.removeAll()
    }

    func relayout() {
        let newLayout = NotchLayout.current()
        let modeChanged = newLayout.hasNotch != layout.hasNotch
        layout = newLayout
        closeDropdown()

        if modeChanged {
            // Notch appeared or vanished (e.g. external display, lid open/close):
            // swap the whole presentation.
            tearDownPresentation()
            buildPresentation()
        } else if layout.hasNotch {
            barPanel?.setFrame(layout.windowFrame, display: true)
        }
        // Tray mode needs no repositioning — the menu bar owns placement.
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
        NSLog("[gitnotch] refresh timer scheduled every %.0fs", interval)
    }

    func refreshNow(reason: String = "manual") {
        NSLog("[gitnotch] heartbeat — refresh requested (%@)", reason)
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

    // MARK: Status item (notch-less Macs)

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "com.spaceship.gitnotch.status"  // persists position, enables ⌘-drag
        if let button = item.button {
            let host = NSHostingView(rootView: StatusButtonView(state: state))
            button.addSubview(host)
            button.target = self
            button.action = #selector(statusItemClicked)
        }
        statusItem = item
        resizeStatusButton()

        // The hosting view redraws itself as counts change, but the status item
        // won't re-measure an arbitrary subview — resize its width by hand.
        Publishers.Merge(
            state.$reviewRequested.map { _ in () },
            state.$openPRs.map { _ in () }
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] in self?.resizeStatusButton() }
        .store(in: &cancellables)
    }

    /// Fit the status item's width to its SwiftUI content and pin the hosting
    /// view to fill the button.
    private func resizeStatusButton() {
        guard let button = statusItem?.button,
              let host = button.subviews.first as? NSHostingView<StatusButtonView> else { return }
        let size = host.fittingSize
        statusItem?.length = size.width
        host.frame = CGRect(x: 0, y: 0, width: size.width, height: button.bounds.height)
    }

    @objc private func statusItemClicked() {
        guard let button = statusItem?.button, let window = button.window else { return }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        if openSide != nil { closeDropdown(); return }
        openTrayDropdown(anchor: anchor)
    }

    /// The frame of the screen whose menu bar the anchor sits under. Prefers the
    /// screen containing the anchor's midpoint; falls back to the one with the
    /// most overlap so a partially off-screen anchor still lands correctly.
    private func screenContaining(_ anchor: CGRect) -> CGRect? {
        let point = CGPoint(x: anchor.midX, y: anchor.midY)
        if let hit = NSScreen.screens.first(where: { $0.frame.contains(point) }) {
            return hit.frame
        }
        func overlap(_ s: NSScreen) -> CGFloat {
            let r = s.frame.intersection(anchor)
            return r.isNull ? 0 : r.width * r.height
        }
        return NSScreen.screens.max { overlap($0) < overlap($1) }?.frame
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

        installOutsideClickMonitor()
    }

    /// The combined dropdown for tray mode: one popover under the status item
    /// with a Review / Yours switcher, positioned by its menu-bar anchor.
    private func openTrayDropdown(anchor: CGRect) {
        closeDropdown()
        openSide = .left  // marks the dropdown open; the switcher picks the list

        let width: CGFloat = 400
        let maxHeight: CGFloat = 460
        // Clamp to the screen the icon was actually clicked on, not layout.screen
        // (that's NSScreen.main — the focused-window display, which may differ
        // when multiple/mirrored monitors are attached).
        let f = screenContaining(anchor) ?? layout.screen.frame
        var x = anchor.midX - width / 2
        x = min(max(x, f.minX + 8), f.maxX - width - 8)

        let root = DropdownView(side: .left, maxHeight: maxHeight, showsSideSwitcher: true)
            .environmentObject(state)
            .environmentObject(self)
        let host = NSHostingView(rootView: root)

        // Size the popover to its content so it hugs the menu bar (no empty
        // voids): the "all clear" state is compact, a populated list fills to
        // maxHeight and scrolls. A SwiftUI List reports a near-zero fittingSize,
        // so we can't measure a populated popover — key off whether any list
        // (either side, either draft filter) has PRs and give it the full
        // height; only fall back to measuring for the genuine all-clear state.
        let hasContent = !state.reviewRequested.isEmpty
            || !state.openPRs.isEmpty
            || !state.myAttentionDrafts.isEmpty
        let height: CGFloat
        if hasContent {
            height = maxHeight
        } else {
            host.layoutSubtreeIfNeeded()
            height = min(maxHeight, max(160, host.fittingSize.height))
        }
        let y = anchor.minY - height

        let panel = makePanel(frame: CGRect(x: x, y: y, width: width, height: height))
        panel.hasShadow = true
        panel.contentView = host
        panel.orderFrontRegardless()
        dropdown = panel

        installOutsideClickMonitor()
    }

    /// Dismiss when the user clicks anywhere outside our windows.
    private func installOutsideClickMonitor() {
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
        panel.title = "Git Notch — Settings"
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
