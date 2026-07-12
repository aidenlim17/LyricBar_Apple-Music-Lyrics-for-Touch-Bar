import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var touchBarController: TouchBarController?
    private weak var viewModel: LyricBarViewModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive(_:)),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        debugLog("Touch Bar 지원 여부: 공개 API 사용 가능, 실제 표시는 Touch Bar 하드웨어와 활성 앱 상태에 따름")
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        touchBarController?.removeFromControlStrip()
        viewModel?.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        bringMainWindowForward()
        return true
    }

    func configure(viewModel: LyricBarViewModel) {
        guard self.viewModel !== viewModel else {
            debugLog("동일 ViewModel 재연결: \(viewModel.debugIdentifier)")
            viewModel.start()
            attachTouchBarToVisibleWindows()
            touchBarController?.showInControlStrip()
            return
        }

        self.viewModel = viewModel
        debugLog("ViewModel 구성: \(viewModel.debugIdentifier)")
        self.touchBarController = TouchBarController(viewModel: viewModel, appDelegate: self)
        viewModel.start()
        attachTouchBarToVisibleWindows()
        touchBarController?.showInControlStrip()
    }

    func bringMainWindowForward() {
        NSApp.activate(ignoringOtherApps: true)

        let candidate = NSApp.windows.first { window in
            window.canBecomeKey && !window.isExcludedFromWindowsMenu
        }

        guard let window = candidate else {
            debugLog("앞으로 가져올 메인 창을 아직 찾지 못함")
            return
        }

        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        attachTouchBar(to: window)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        debugLog("앱 활성화")
        touchBarController?.refresh()
        attachTouchBarToVisibleWindows()
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        attachTouchBar(to: window)
        touchBarController?.refresh()
    }

    private func attachTouchBarToVisibleWindows() {
        for window in NSApp.windows where window.canBecomeKey {
            attachTouchBar(to: window)
        }
    }

    private func attachTouchBar(to window: NSWindow) {
        guard let touchBarController else { return }
        window.touchBar = touchBarController.touchBar
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        guard UserDefaults.standard.bool(forKey: "LyricBarVerboseLogging") else { return }
        NSLog("[LyricBar AppDelegate] %@", message)
        #endif
    }
}
