import AppKit
import Combine
import Darwin

@MainActor
final class TouchBarController: NSObject, NSTouchBarDelegate {
    private weak var viewModel: LyricBarViewModel?
    private weak var appDelegate: AppDelegate?
    private var cancellables = Set<AnyCancellable>()
    private let systemTrayPresenter = TouchBarSystemTrayPresenter()

    private let currentButton = NSButton(title: "", target: nil, action: nil)
    private let systemTrayButton = NSButton(title: "", target: nil, action: nil)
    private lazy var systemTrayItem: NSCustomTouchBarItem = {
        let item = NSCustomTouchBarItem(identifier: .lyricBarSystemTray)
        item.view = systemTrayButton
        item.customizationLabel = "LyricBar"
        return item
    }()

    lazy var touchBar: NSTouchBar = {
        let touchBar = NSTouchBar()
        touchBar.delegate = self
        touchBar.customizationIdentifier = .lyricBar
        touchBar.defaultItemIdentifiers = [.lyricBarCurrent, .flexibleSpace]
        touchBar.customizationAllowedItemIdentifiers = [.lyricBarCurrent, .flexibleSpace]
        debugLog("Touch Bar 생성")
        return touchBar
    }()

    init(viewModel: LyricBarViewModel, appDelegate: AppDelegate) {
        self.viewModel = viewModel
        self.appDelegate = appDelegate
        super.init()
        configureViews()
        bind(to: viewModel)
        debugLog("ViewModel 연결: \(viewModel.debugIdentifier)")
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        switch identifier {
        case .lyricBarCurrent:
            return customItem(identifier, view: currentButton, label: "현재 가사")
        default:
            return nil
        }
    }

    func refresh() {
        guard let viewModel else { return }
        update(from: viewModel)
    }

    func showInControlStrip() {
        systemTrayPresenter.show(systemTrayItem)
        debugLog("Control Strip 아이템 등록")
    }

    func removeFromControlStrip() {
        systemTrayPresenter.remove(systemTrayItem)
        debugLog("Control Strip 아이템 제거")
    }

    func presentSystemModalFromControlStrip() {
        systemTrayPresenter.present(touchBar, for: systemTrayItem)
        debugLog("Control Strip에서 Touch Bar 표시")
    }

    @objc private func openLyricBar() {
        debugLog("앱 활성화")
        appDelegate?.bringMainWindowForward()
    }

    @objc private func openLyricsTouchBar() {
        presentSystemModalFromControlStrip()
    }

    private func configureViews() {
        currentButton.target = self
        currentButton.action = #selector(openLyricBar)
        currentButton.title = "Apple Music 확인 중..."
        currentButton.isBordered = false
        currentButton.alignment = .left
        currentButton.font = .systemFont(ofSize: 18, weight: .light)
        currentButton.lineBreakMode = .byTruncatingTail
        currentButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        currentButton.setContentHuggingPriority(.defaultLow, for: .horizontal)
        currentButton.setAccessibilityLabel("현재 가사")
        currentButton.toolTip = "LyricBar 열기"

        currentButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 420).isActive = true
        currentButton.widthAnchor.constraint(lessThanOrEqualToConstant: 760).isActive = true

        systemTrayButton.target = self
        systemTrayButton.action = #selector(openLyricsTouchBar)
        systemTrayButton.isBordered = false
        systemTrayButton.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "LyricBar")
        systemTrayButton.imagePosition = .imageOnly
        systemTrayButton.setAccessibilityLabel("LyricBar 가사 열기")
        systemTrayButton.toolTip = "LyricBar 가사"
        systemTrayButton.widthAnchor.constraint(equalToConstant: 30).isActive = true
    }

    private func bind(to viewModel: LyricBarViewModel) {
        viewModel.$currentLyric
            .combineLatest(viewModel.$statusText, viewModel.$isTouchBarLyricsEnabled)
        .receive(on: RunLoop.main)
        .sink { [weak self, weak viewModel] _, _, _ in
            guard let self, let viewModel else { return }
            self.update(from: viewModel)
        }
        .store(in: &cancellables)
    }

    private func update(from viewModel: LyricBarViewModel) {
        guard viewModel.isTouchBarLyricsEnabled else {
            currentButton.title = "Touch Bar 가사 표시 꺼짐"
            return
        }

        switch viewModel.statusText {
        case LyricsState.musicAppNotRunning.label:
            currentButton.title = "Apple Music을 실행하세요"
        case LyricsState.noTrack.label:
            currentButton.title = "재생 중인 곡 없음"
        case LyricsState.loading.label:
            currentButton.title = "가사 검색 중..."
        case LyricsState.plainLyrics.label:
            currentButton.title = "시간 동기화되지 않은 가사"
        case LyricsState.noLyrics.label:
            currentButton.title = "가사를 찾을 수 없음"
        case LyricsState.networkError("").label, LyricsState.parsingError("").label:
            currentButton.title = "가사 불러오기 실패"
        default:
            currentButton.title = viewModel.currentLyric.isEmpty ? " " : viewModel.currentLyric
        }

        debugLog("현재 가사 갱신: \(viewModel.currentLyric)")
    }

    private func customItem(_ identifier: NSTouchBarItem.Identifier, view: NSView, label: String) -> NSTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: identifier)
        item.view = view
        item.customizationLabel = label
        view.setAccessibilityLabel(label)
        return item
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        guard UserDefaults.standard.bool(forKey: "LyricBarVerboseLogging") else { return }
        NSLog("[LyricBar TouchBar] %@", message)
        #endif
    }
}

private final class TouchBarSystemTrayPresenter {
    private typealias TrayItemFunction = @convention(c) (AnyClass, Selector, NSTouchBarItem) -> Void
    private typealias PresenceFunction = @convention(c) (NSString, Bool) -> Void
    private typealias PresentFunction = @convention(c) (AnyClass, Selector, NSTouchBar, Int64, NSString) -> Void
    private typealias DismissFunction = @convention(c) (AnyClass, Selector, NSTouchBar) -> Void
    private typealias CloseBoxFunction = @convention(c) (Bool) -> Void

    private let dfrHandle: UnsafeMutableRawPointer?
    private let setControlStripPresence: PresenceFunction?
    private let setCloseBoxWhenFrontMost: CloseBoxFunction?
    private var isInControlStrip = false

    init() {
        dfrHandle = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_LAZY)
        if let dfrHandle,
           let symbol = dlsym(dfrHandle, "DFRElementSetControlStripPresenceForIdentifier") {
            setControlStripPresence = unsafeBitCast(symbol, to: PresenceFunction.self)
        } else {
            setControlStripPresence = nil
        }

        if let dfrHandle,
           let symbol = dlsym(dfrHandle, "DFRSystemModalShowsCloseBoxWhenFrontMost") {
            setCloseBoxWhenFrontMost = unsafeBitCast(symbol, to: CloseBoxFunction.self)
        } else {
            setCloseBoxWhenFrontMost = nil
        }
    }

    deinit {
        if let dfrHandle {
            dlclose(dfrHandle)
        }
    }

    func show(_ item: NSTouchBarItem) {
        setCloseBoxWhenFrontMost?(false)
        callTouchBarItemClassMethod("addSystemTrayItem:", item: item)
        setControlStripPresence?(item.identifier.rawValue as NSString, true)
        isInControlStrip = true
    }

    func remove(_ item: NSTouchBarItem) {
        dismiss(nil)
        setControlStripPresence?(item.identifier.rawValue as NSString, false)
        callTouchBarItemClassMethod("removeSystemTrayItem:", item: item)
        isInControlStrip = false
    }

    func present(_ touchBar: NSTouchBar, for item: NSTouchBarItem) {
        setCloseBoxWhenFrontMost?(false)
        guard let method = class_getClassMethod(NSTouchBar.self, NSSelectorFromString("presentSystemModalTouchBar:placement:systemTrayItemIdentifier:")) else {
            return
        }

        let implementation = method_getImplementation(method)
        let function = unsafeBitCast(implementation, to: PresentFunction.self)
        function(NSTouchBar.self, NSSelectorFromString("presentSystemModalTouchBar:placement:systemTrayItemIdentifier:"), touchBar, 0, item.identifier.rawValue as NSString)
    }

    func dismiss(_ touchBar: NSTouchBar?) {
        guard let touchBar,
              let method = class_getClassMethod(NSTouchBar.self, NSSelectorFromString("dismissSystemModalTouchBar:")) else {
            return
        }

        let implementation = method_getImplementation(method)
        let function = unsafeBitCast(implementation, to: DismissFunction.self)
        function(NSTouchBar.self, NSSelectorFromString("dismissSystemModalTouchBar:"), touchBar)
    }

    private func callTouchBarItemClassMethod(_ selectorName: String, item: NSTouchBarItem) {
        let selector = NSSelectorFromString(selectorName)
        guard let method = class_getClassMethod(NSTouchBarItem.self, selector) else {
            return
        }

        let implementation = method_getImplementation(method)
        let function = unsafeBitCast(implementation, to: TrayItemFunction.self)
        function(NSTouchBarItem.self, selector, item)
    }
}
