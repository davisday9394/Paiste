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
        
        // 重置当前选中项索引
        currentItemIndex = 0
        
        // 获取屏幕尺寸和窗口尺寸
        guard let screen = NSScreen.main else { return }
        // 使用完整屏幕区域，窗口层级已设置为statusBar确保在dock之上
        let screenFrame = screen.frame
        let windowFrame = window.frame
        
        // 从底部弹出的实现
        showFromBottom(window: window, screenFrame: screenFrame, windowFrame: windowFrame)
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