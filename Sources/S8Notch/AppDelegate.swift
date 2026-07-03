import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = NotchController()
        self.controller = controller
        controller.start()

        // Reposition the notch bar if the display configuration changes
        // (e.g. plugging in an external monitor, resolution change).
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak controller] _ in
            Task { @MainActor in controller?.relayout() }
        }
    }
}
