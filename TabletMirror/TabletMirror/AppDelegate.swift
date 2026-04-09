import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_: Notification) {
        let viewController = ScreenViewController()
        window = NSWindow(contentViewController: viewController)
        window.delegate = viewController
        window.title = "Tablet Mirror"
        window.makeKeyAndOrderFront(nil)
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .white
        window.contentMinSize = CGSize(width: 320, height: 200)
        window.styleMask.insert(.resizable)
        window.collectionBehavior.insert(.fullScreenNone)

        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appSubMenu = NSMenu(title: "MainMenu")
        appSubMenu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApp.terminate), keyEquivalent: "q"))
        appMenuItem.submenu = appSubMenu

        let streamMenuItem = NSMenuItem()
        let streamSubMenu = NSMenu(title: "Stream")
        let sendFrameItem = NSMenuItem(
            title: "Send Frame (Phase 1)",
            action: #selector(sendStaticFrame),
            keyEquivalent: "s"
        )
        streamSubMenu.addItem(sendFrameItem)
        streamMenuItem.submenu = streamSubMenu

        mainMenu.items = [appMenuItem, streamMenuItem]
        NSApplication.shared.mainMenu = mainMenu
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        return true
    }

    @objc private func sendStaticFrame() {
        guard let vc = window.contentViewController as? ScreenViewController else { return }
        vc.sendStaticFrame()
    }
}
