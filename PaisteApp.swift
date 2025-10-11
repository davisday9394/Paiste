import SwiftUI
import ServiceManagement

// 自定义窗口类，确保能接收键盘事件
class ClipboardWindow: NSWindow {
    override var canBecomeKey: Bool {
        return true
    }
    
    override var canBecomeMain: Bool {
        return true
    }
}

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
    static var shared: AppDelegate?
    
    var statusItem: NSStatusItem?
    var clipboardWindow: ClipboardWindow?
    private var shortcutManager = GlobalShortcutManager()
    private var currentItemIndex = 0
    
    // 用于通知 ClipboardView 重置选中索引的触发器
    @Published var resetSelectionTrigger = false
    
    // 记录显示剪切板窗口前的活跃应用程序
    private var previousActiveApp: NSRunningApplication?
    
    override init() {
        super.init()
        AppDelegate.shared = self
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 创建菜单栏图标
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Paiste")
            button.action = #selector(togglePopover)
        }
        
        // 创建底部弹出窗口
        setupClipboardWindow()
        
        // 设置全局快捷键
        setupGlobalShortcut()
        
        // 隐藏Dock图标
        NSApp.setActivationPolicy(.accessory)
        
        // 监听ESC键关闭弹窗
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // ESC键
                if let window = self?.clipboardWindow, window.isVisible {
                    self?.hideClipboardWindow()
                    return nil
                }
            }
            return event
        }
    }
    
    @objc func togglePopover() {
        toggleClipboardWindow()
    }
    
    func setupGlobalShortcut() {
        // 注册Cmd+Shift+V快捷键
        shortcutManager.register(
            keyCode: KeyCode.v,
            modifiers: KeyModifier.command | KeyModifier.shift,
            handler: {
            // 使用静态引用确保安全访问
            guard let appDelegate = AppDelegate.shared else { return }
            
            // 确保窗口已初始化
            if appDelegate.clipboardWindow == nil {
                appDelegate.setupClipboardWindow()
            }
            
            guard let window = appDelegate.clipboardWindow else { return }
            
            if window.isVisible {
                // 如果弹窗已显示，切换选择的项目
                appDelegate.selectNextItem()
            } else {
                // 如果弹窗未显示，显示弹窗
                appDelegate.toggleClipboardWindow()
            }
        })
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
    
    private func setupClipboardWindow() {
        // 获取主屏幕信息
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame  // 使用完整屏幕区域
        
        // 设置窗口尺寸（铺满整个屏幕宽度）
        let windowWidth: CGFloat = screenFrame.width
        let windowHeight: CGFloat = 300
        
        // 计算窗口位置（紧贴底部）
        let windowX = screenFrame.minX
        let windowY = screenFrame.minY
        
        let windowRect = NSRect(x: windowX, y: windowY, width: windowWidth, height: windowHeight)
        
        // 创建窗口
        clipboardWindow = ClipboardWindow(
            contentRect: windowRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        guard let window = clipboardWindow else { return }
        
        // 设置窗口属性
        window.level = .statusBar  // 使用statusBar级别确保在dock栏之上
        window.isOpaque = false
        window.backgroundColor = NSColor.clear
        window.hasShadow = true
        window.isMovable = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.acceptsMouseMovedEvents = true
        
        // 设置内容视图
        let contentView = NSHostingView(rootView: ClipboardView())
        window.contentView = contentView
        
        // 初始状态隐藏窗口
        window.orderOut(nil)
    }
    
    private func toggleClipboardWindow() {
        guard let window = clipboardWindow else { return }
        
        if window.isVisible {
            hideClipboardWindow()
        } else {
            showClipboardWindow()
        }
    }
    
    private func showClipboardWindow() {
        guard let window = clipboardWindow else { return }
        
        // 记录当前活跃的应用程序（在显示剪切板窗口前）
        previousActiveApp = NSWorkspace.shared.frontmostApplication
        
        // 重置当前选中项索引
        currentItemIndex = 0
        
        // 触发 ClipboardView 重置选中索引
        resetSelectionTrigger.toggle()
        
        // 获取当前鼠标位置所在的屏幕
        guard let screen = getCurrentScreen() else { return }
        // 使用完整屏幕区域，窗口层级已设置为statusBar确保在dock之上
        let screenFrame = screen.frame
        
        // 动态调整窗口尺寸以适应当前屏幕
        let windowWidth = screenFrame.width
        let windowHeight: CGFloat = 300
        let windowX = screenFrame.minX
        let windowY = screenFrame.minY
        
        let newWindowFrame = NSRect(x: windowX, y: windowY, width: windowWidth, height: windowHeight)
        window.setFrame(newWindowFrame, display: false)
        
        let windowFrame = window.frame
        
        // 从底部弹出的实现
        showFromBottom(window: window, screenFrame: screenFrame, windowFrame: windowFrame)
    }
    
    // 获取当前鼠标位置所在的屏幕
    private func getCurrentScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        
        // 遍历所有屏幕，找到包含鼠标位置的屏幕
        for screen in NSScreen.screens {
            if screen.frame.contains(mouseLocation) {
                return screen
            }
        }
        
        // 如果没有找到，返回主屏幕作为备选
        return NSScreen.main
    }
    
    // 从顶部弹出的实现
    private func showFromTop(window: ClipboardWindow, screenFrame: NSRect, windowFrame: NSRect) {
        // 设置初始位置（在屏幕顶部上方）
        let finalX = screenFrame.minX
        let finalY = screenFrame.maxY - windowFrame.height
        let initialY = screenFrame.maxY + 20
        
        // 设置初始状态
        window.setFrame(NSRect(x: finalX, y: initialY, width: windowFrame.width, height: windowFrame.height), display: false)
        window.alphaValue = 0.0
        
        // 显示窗口并激活
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        // 确保窗口能接收键盘事件
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            window.makeKey()
        }
        
        // 添加滑入和淡入动画（无复杂的完成回调）
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1.0
            window.animator().setFrame(NSRect(x: finalX, y: finalY, width: windowFrame.width, height: windowFrame.height), display: true)
        }
        // 注意：这里没有复杂的完成回调，减少了内存管理问题
    }
    
    // 从底部弹出的实现（原有实现，保留用于对比）
    private func showFromBottom(window: ClipboardWindow, screenFrame: NSRect, windowFrame: NSRect) {
        // 设置初始位置（在屏幕底部下方）
        let finalX = screenFrame.minX
        let finalY = screenFrame.minY
        let initialY = screenFrame.minY - windowFrame.height - 20
        
        // 设置初始状态
        window.setFrame(NSRect(x: finalX, y: initialY, width: windowFrame.width, height: windowFrame.height), display: false)
        window.alphaValue = 0.0
        
        // 显示窗口并激活
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        // 确保窗口能接收键盘事件
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            window.makeKey()
        }
        
        // 添加滑入和淡入动画
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1.0
            window.animator().setFrame(NSRect(x: finalX, y: finalY, width: windowFrame.width, height: windowFrame.height), display: true)
        }
    }
    
    func hideClipboardWindow() {
        guard let window = clipboardWindow else { return }
        
        // 从底部隐藏的实现
        hideToBottom(window: window)
        
        // 恢复之前活跃应用程序的焦点
        restorePreviousAppFocus()
    }
    
    private func restorePreviousAppFocus() {
        // 延迟一小段时间确保窗口隐藏动画完成
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self = self, let previousApp = self.previousActiveApp else { return }
            
            // 尝试激活之前的应用程序
            previousApp.activate(options: [.activateIgnoringOtherApps])
            
            // 清除记录的应用程序引用
            self.previousActiveApp = nil
        }
    }
    
    // 从顶部隐藏的实现
    private func hideToTop(window: ClipboardWindow) {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let currentFrame = window.frame
        
        // 计算滑出目标位置（屏幕顶部上方）
        let targetY = screenFrame.maxY + 20
        let targetFrame = NSRect(x: currentFrame.minX, y: targetY, width: currentFrame.width, height: currentFrame.height)
        
        // 添加滑出和淡出动画（简化的完成回调）
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0.0
            window.animator().setFrame(targetFrame, display: true)
        }) {
            // 简化的完成回调，避免复杂的self引用
            window.orderOut(nil)
            window.alphaValue = 1.0
            // 不需要复杂的位置重置，因为下次显示时会重新计算
        }
    }
    
    // 从底部隐藏的实现（原有实现，保留用于对比）
    private func hideToBottom(window: ClipboardWindow) {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let currentFrame = window.frame
        
        // 计算滑出目标位置（屏幕底部下方）
        let targetY = screenFrame.minY - currentFrame.height - 20
        let targetFrame = NSRect(x: currentFrame.minX, y: targetY, width: currentFrame.width, height: currentFrame.height)
        
        // 添加滑出和淡出动画
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0.0
            window.animator().setFrame(targetFrame, display: true)
        }) { [weak self] in
            // 复杂的完成回调，可能导致内存管理问题
            guard let self = self, let window = self.clipboardWindow else { return }
            window.orderOut(nil)
            window.alphaValue = 1.0
            // 重置窗口位置到正确的显示位置，为下次显示做准备
            let correctFrame = NSRect(x: screenFrame.minX, y: screenFrame.minY, width: screenFrame.width, height: 300)
            window.setFrame(correctFrame, display: false)
        }
    }
}