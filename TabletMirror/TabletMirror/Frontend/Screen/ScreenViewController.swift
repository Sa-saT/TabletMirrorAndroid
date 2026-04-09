import Cocoa

class ScreenViewController: NSViewController, NSWindowDelegate {
    private var display: CGVirtualDisplay!
    private var stream: CGDisplayStream?
    let streamSender = StreamSender()

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupVirtualDisplay()
        setupScreenNotification()
        setupADB()
    }

    // MARK: - Virtual Display

    private func setupVirtualDisplay() {
        let descriptor = CGVirtualDisplayDescriptor()
        descriptor.setDispatchQueue(DispatchQueue.main)
        descriptor.name = "Tablet Display"
        descriptor.maxPixelsWide = 1280
        descriptor.maxPixelsHigh = 800
        descriptor.sizeInMillimeters = CGSize(width: 256, height: 160)
        descriptor.productID = 0x1234
        descriptor.vendorID = 0x3456
        descriptor.serialNum = 0x0001

        display = CGVirtualDisplay(descriptor: descriptor)

        let settings = CGVirtualDisplaySettings()
        settings.hiDPI = 0
        settings.modes = [
            CGVirtualDisplayMode(width: 1280, height: 800, refreshRate: 30),
        ]
        display.apply(settings)
    }

    // MARK: - Screen Capture Stream

    private func setupScreenNotification() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        // 初回起動時に仮想ディスプレイがすぐ認識されない場合があるため少し待って更新
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.updateStream()
        }
    }

    @objc private func screensDidChange() {
        updateStream()
    }

    private func updateStream() {
        guard let screen = NSScreen.screens.first(where: { $0.displayID == display.displayID }) else {
            return
        }
        let resolution = screen.frame.size
        let scaleFactor = screen.backingScaleFactor

        stream = nil
        view.window?.setContentSize(resolution)
        view.window?.contentAspectRatio = resolution
        view.window?.center()

        let newStream = CGDisplayStream(
            dispatchQueueDisplay: display.displayID,
            outputWidth: Int(resolution.width * scaleFactor),
            outputHeight: Int(resolution.height * scaleFactor),
            pixelFormat: 1_111_970_369,
            properties: [CGDisplayStream.showCursor: true] as CFDictionary,
            queue: .main,
            handler: { [weak self] _, _, frameSurface, _ in
                if let surface = frameSurface {
                    // デバッグ用ミラーウィンドウ表示 (Phase 2でエンコーダーに差し替え)
                    self?.view.layer?.contents = surface
                }
            }
        )
        stream = newStream
        newStream?.start()
    }

    // MARK: - ADB + Streaming

    private func setupADB() {
        ADBManager.shared.setupForward { [weak self] success, message in
            if success {
                self?.view.window?.title = "Tablet Mirror — ADB OK"
                self?.streamSender.connect()
            } else {
                self?.view.window?.title = "Tablet Mirror — ADB NG: \(message)"
            }
        }

        streamSender.onStatusChange = { [weak self] status in
            self?.view.window?.title = "Tablet Mirror — \(status)"
        }
    }

    // Phase 1: 静止画を1枚送信 (AppDelegateのメニューから呼ばれる)
    func sendStaticFrame() {
        streamSender.sendStaticFrame(displayID: display.displayID)
    }

    // MARK: - NSWindowDelegate

    func windowWillResize(_ window: NSWindow, to frameSize: NSSize) -> NSSize {
        let snappingOffset: CGFloat = 30
        let contentSize = window.contentRect(forFrameRect: NSRect(origin: .zero, size: frameSize)).size
        let targetResolution = CGSize(width: 1280, height: 800)
        guard abs(contentSize.width - targetResolution.width) < snappingOffset else {
            return frameSize
        }
        return window.frameRect(forContentRect: NSRect(origin: .zero, size: targetResolution)).size
    }
}
