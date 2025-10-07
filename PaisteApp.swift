import SwiftUI
import ServiceManagement

@main
struct PaisteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    private var shortcutManager = GlobalShortcutManager()
    private var currentItemIndex = 0
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 创建菜单栏图标
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Paiste")
            button.action = #selector(togglePopover)
        }
        
        // 创建弹出窗口
        popover = NSPopover()
        
        // 获取当前活动屏幕的宽度
        let activeScreen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let screenWidth = activeScreen?.frame.width ?? 1200
        
        // 使用固定宽度而不是百分比，确保在任何屏幕上都有足够的宽度
        popover?.contentSize = NSSize(width: min(screenWidth - 40, 1800), height: 500)
        popover?.behavior = .transient
        popover?.contentViewController = NSHostingController(rootView: ClipboardView())
        
        // 设置全局快捷键
        setupGlobalShortcut()
        
        // 隐藏Dock图标
        NSApp.setActivationPolicy(.accessory)
        
        // 监听ESC键关闭弹窗
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // ESC键
                if let popover = self?.popover, popover.isShown {
                    popover.performClose(nil)
                    return nil
                }
            }
            return event
        }
    }
    
    @objc func togglePopover() {
        if let button = statusItem?.button, let popover = popover {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                popover.contentViewController?.view.window?.makeKey()
                // 重置当前选中项索引
                currentItemIndex = 0
            }
        }
    }
    
    func setupGlobalShortcut() {
        // 注册Cmd+Shift+V快捷键
        shortcutManager.register(
            keyCode: KeyCode.v,
            modifiers: KeyModifier.command | KeyModifier.shift
        ) { [weak self] in
            guard let self = self else { return }
            
            if let popover = self.popover {
                if popover.isShown {
                    // 如果弹窗已显示，切换选择的项目
                    self.selectNextItem()
                } else {
                    // 如果弹窗未显示，显示弹窗
                    self.togglePopover()
                }
            }
        }
    }
    
    private func selectNextItem() {
        let items = ClipboardManager.shared.items
        guard !items.isEmpty else { return }
        
        // 切换到下一个项目
        currentItemIndex = (currentItemIndex + 1) % items.count
        
        // 获取当前项目并粘贴
        let currentItem = items[currentItemIndex]
        currentItem.paste()
    }
}