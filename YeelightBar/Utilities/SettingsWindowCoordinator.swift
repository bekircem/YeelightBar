import AppKit
import SwiftUI

@MainActor
final class SettingsWindowCoordinator: ObservableObject {
    private weak var window: NSWindow?
    private var pendingPresentationRevision: Int?
    private let defaults: UserDefaults
    private let activateApplication: () -> Void
    private let visibleFrameProvider: (NSWindow) -> NSRect?
    private let deferAction: (@escaping @MainActor () -> Void) -> Void

    @Published private(set) var presentationRevision = 0

    init(
        defaults: UserDefaults = .standard,
        activateApplication: @escaping () -> Void = {
            NSApp.activate()
        },
        visibleFrameProvider: @escaping (NSWindow) -> NSRect? = { window in
            window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        },
        deferAction: @escaping (@escaping @MainActor () -> Void) -> Void = { action in
            Task { @MainActor in
                await Task.yield()
                action()
            }
        }
    ) {
        self.defaults = defaults
        self.activateApplication = activateApplication
        self.visibleFrameProvider = visibleFrameProvider
        self.deferAction = deferAction
    }

    func present(openSettings: () -> Void) {
        presentationRevision &+= 1
        let revision = presentationRevision
        pendingPresentationRevision = revision
        openSettings()
        schedulePresentationAttempt(for: revision)
    }

    func register(window: NSWindow) {
        self.window = window
        configureWindowProperties(window)

        deferAction { [weak self, weak window] in
            guard let self, let window, self.window === window else { return }
            self.applyGeometryPolicy(to: window)

            if let revision = self.pendingPresentationRevision {
                self.completePresentation(revision: revision, window: window)
            }
        }
    }

    private func schedulePresentationAttempt(for revision: Int) {
        deferAction { [weak self] in
            guard let self, let window = self.window else { return }
            self.completePresentation(revision: revision, window: window)
        }
    }

    private func completePresentation(revision: Int, window: NSWindow) {
        guard pendingPresentationRevision == revision else { return }

        applyGeometryPolicy(to: window)
        repairFrameIfNeeded(for: window)
        activateApplication()

        if window.isMiniaturized {
            window.deminiaturize(nil)
        }

        window.makeKeyAndOrderFront(nil)
        pendingPresentationRevision = nil
    }

    private func configureWindowProperties(_ window: NSWindow) {
        window.styleMask.formUnion([.titled, .closable, .miniaturizable, .resizable])
        window.title = "YeelightBar Settings"
        window.titleVisibility = .visible

        for buttonType in NSWindow.ButtonType.settingsWindowButtons {
            window.standardWindowButton(buttonType)?.isHidden = false
        }

        updateMinimumContentSize(for: window)
    }

    private func applyGeometryPolicy(to window: NSWindow) {
        updateMinimumContentSize(for: window)

        guard let visibleFrame = visibleFrame(for: window) else { return }

        if defaults.integer(forKey: SettingsWindowGeometry.migrationVersionKey)
            < SettingsWindowGeometry.migrationVersion {
            let contentRect = NSRect(origin: .zero, size: SettingsWindowGeometry.idealContentSize)
            let idealWindowSize = window.frameRect(forContentRect: contentRect).size
            let frame = SettingsWindowGeometry.centeredFrame(
                size: idealWindowSize,
                in: visibleFrame
            )
            window.setFrame(frame, display: false)
            defaults.set(
                SettingsWindowGeometry.migrationVersion,
                forKey: SettingsWindowGeometry.migrationVersionKey
            )
        } else {
            repairFrameIfNeeded(for: window)
        }
    }

    private func updateMinimumContentSize(for window: NSWindow) {
        guard let visibleFrame = visibleFrame(for: window) else {
            window.contentMinSize = SettingsWindowGeometry.minimumContentSize
            return
        }

        let safeFrame = SettingsWindowGeometry.safeFrame(in: visibleFrame)
        let maximumContentSize = window.contentRect(
            forFrameRect: NSRect(origin: .zero, size: safeFrame.size)
        ).size
        window.contentMinSize = NSSize(
            width: max(
                1,
                min(SettingsWindowGeometry.minimumContentSize.width, maximumContentSize.width)
            ),
            height: max(
                1,
                min(SettingsWindowGeometry.minimumContentSize.height, maximumContentSize.height)
            )
        )
    }

    private func repairFrameIfNeeded(for window: NSWindow) {
        guard let visibleFrame = visibleFrame(for: window) else { return }

        let repairedFrame = SettingsWindowGeometry.fittedFrame(
            window.frame,
            in: visibleFrame
        )

        if !NSEqualRects(repairedFrame, window.frame) {
            window.setFrame(repairedFrame, display: false)
        }
    }

    private func visibleFrame(for window: NSWindow) -> NSRect? {
        visibleFrameProvider(window)
    }
}

private extension NSWindow.ButtonType {
    static let settingsWindowButtons: [NSWindow.ButtonType] = [
        .closeButton,
        .miniaturizeButton,
        .zoomButton
    ]
}

enum SettingsWindowGeometry {
    static let migrationVersion = 2
    static let migrationVersionKey = "settings.window.geometryVersion"
    static let idealContentSize = NSSize(width: 800, height: 540)
    static let minimumContentSize = NSSize(width: 720, height: 480)
    static let screenMargin: CGFloat = 24

    static func centeredFrame(
        size: NSSize,
        in visibleFrame: NSRect,
        margin: CGFloat = screenMargin
    ) -> NSRect {
        let safeFrame = safeFrame(in: visibleFrame, margin: margin)
        let fittedSize = NSSize(
            width: min(max(size.width, 1), safeFrame.width),
            height: min(max(size.height, 1), safeFrame.height)
        )

        return NSRect(
            x: safeFrame.midX - (fittedSize.width / 2),
            y: safeFrame.midY - (fittedSize.height / 2),
            width: fittedSize.width,
            height: fittedSize.height
        )
    }

    static func fittedFrame(
        _ frame: NSRect,
        in visibleFrame: NSRect,
        margin: CGFloat = screenMargin
    ) -> NSRect {
        let safeFrame = safeFrame(in: visibleFrame, margin: margin)
        let width = min(max(frame.width, 1), safeFrame.width)
        let height = min(max(frame.height, 1), safeFrame.height)
        let x = min(max(frame.minX, safeFrame.minX), safeFrame.maxX - width)
        let y = min(max(frame.minY, safeFrame.minY), safeFrame.maxY - height)

        return NSRect(x: x, y: y, width: width, height: height)
    }

    static func safeFrame(
        in visibleFrame: NSRect,
        margin: CGFloat = screenMargin
    ) -> NSRect {
        let normalizedFrame = visibleFrame.standardized
        let horizontalMargin = min(max(margin, 0), max((normalizedFrame.width - 1) / 2, 0))
        let verticalMargin = min(max(margin, 0), max((normalizedFrame.height - 1) / 2, 0))

        return normalizedFrame.insetBy(dx: horizontalMargin, dy: verticalMargin)
    }
}

struct SettingsWindowReader: NSViewRepresentable {
    let onWindowResolved: @MainActor (NSWindow) -> Void

    func makeNSView(context: Context) -> SettingsWindowReaderView {
        SettingsWindowReaderView(onWindowResolved: onWindowResolved)
    }

    func updateNSView(_ nsView: SettingsWindowReaderView, context: Context) {
        nsView.onWindowResolved = onWindowResolved
        nsView.resolveWindowIfNeeded()
    }
}

final class SettingsWindowReaderView: NSView {
    var onWindowResolved: @MainActor (NSWindow) -> Void
    private weak var resolvedWindow: NSWindow?

    init(onWindowResolved: @escaping @MainActor (NSWindow) -> Void) {
        self.onWindowResolved = onWindowResolved
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        resolveWindowIfNeeded()
    }

    func resolveWindowIfNeeded() {
        guard let window, resolvedWindow !== window else { return }
        resolvedWindow = window
        onWindowResolved(window)
    }
}
