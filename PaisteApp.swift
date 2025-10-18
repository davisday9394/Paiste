import SwiftUI
import ServiceManagement

// 自定义窗口类，确保能接收键盘事件并处理失焦事件
class ClipboardWindow: NSWindow {
    weak var appDelegate: AppDelegate?
    private var globalMouseMonitor: Any?
    private var applicationObserver: NSObjectProtocol?
    private var workspaceObserver: NSObjectProtocol?
    
    override var canBecomeKey: Bool {
        return true
    }
    
    override var canBecomeMain: Bool {
        return true
    }
    
    // 开始监听失焦事件
    func startFocusMonitoring() {
        setupGlobalMouseMonitor()
        setupApplicationSwitchMonitor()
        setupWorkspaceMonitor()
    }
    
    // 停止监听失焦事件
    func stopFocusMonitoring() {
        if let monitor = globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
            globalMouseMonitor = nil
        }
        
        if let observer = applicationObserver {
            NotificationCenter.default.removeObserver(observer)
            applicationObserver = nil
        }
        
        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            workspaceObserver = nil
        }
    }
    
    // 监听全局鼠标点击事件
    private func setupGlobalMouseMonitor() {
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, let appDelegate = self.appDelegate else { return }
            
            // 获取点击位置
            let clickLocation = event.locationInWindow
            let screenLocation = NSEvent.mouseLocation
            
            // 检查点击是否在窗口外部
            if !self.frame.contains(screenLocation) {
                // 点击在窗口外部，隐藏剪切板
                DispatchQueue.main.async {
                    appDelegate.hideClipboardWindow()
                }
            }
        }
    }
    
    // 监听应用切换事件（Cmd+Tab）
    private func setupApplicationSwitchMonitor() {
        applicationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: NSApplication.shared,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, let appDelegate = self.appDelegate else { return }
            // 应用失去焦点，隐藏剪切板
            appDelegate.hideClipboardWindow()
        }
    }
    
    // 监听桌面切换事件（Ctrl+左右键）
    private func setupWorkspaceMonitor() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, let appDelegate = self.appDelegate else { return }
            // 立即清除之前的应用引用，防止跳回原桌面
            appDelegate.clearPreviousApp()
            // 桌面切换，隐藏剪切板但不恢复焦点（避免跳回原桌面）
            appDelegate.hideClipboardWindow(restoreFocus: false)
        }
    }
    
    deinit {
        stopFocusMonitoring()
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
    
    // 单例模式文件锁定
    private var lockFileHandle: FileHandle?
    private let lockFilePath = NSTemporaryDirectory() + "paiste.lock"
    
    override init() {
        super.init()
        AppDelegate.shared = self
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 检查是否已有实例在运行
        if !checkSingleInstance() {
            // 如果已有实例在运行，退出当前实例
            NSApplication.shared.terminate(nil)
            return
        }
        
        // 创建菜单栏图标
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Paiste")
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        // 创建上下文菜单
        setupStatusItemMenu()
        
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
    
    func applicationWillTerminate(_ notification: Notification) {
        // 应用程序退出时释放文件锁
        releaseLockFile()
    }
    
    @objc func statusItemClicked() {
        guard let event = NSApp.currentEvent else { return }
        
        if event.type == .rightMouseUp {
            // 右键点击显示菜单
            statusItem?.menu = createContextMenu()
            statusItem?.button?.performClick(nil)
            statusItem?.menu = nil
        } else {
            // 左键点击切换剪切板窗口
            toggleClipboardWindow()
        }
    }
    
    @objc func togglePopover() {
        toggleClipboardWindow()
    }
    
    private func setupStatusItemMenu() {
        // 初始状态不设置菜单，只在右键时临时显示
    }
    
    private func createContextMenu() -> NSMenu {
        let menu = NSMenu()
        
        // 显示/隐藏剪切板
        let toggleItem = NSMenuItem(title: "显示剪切板", action: #selector(togglePopover), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)
        
        // 分隔线
        menu.addItem(NSMenuItem.separator())
        
        // 退出应用程序
        let quitItem = NSMenuItem(title: "退出 Paiste", action: #selector(quitApplication), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        return menu
    }
    
    @objc private func quitApplication() {
        NSApplication.shared.terminate(nil)
    }
    
    // 检查单例模式 - 确保只有一个应用程序实例在运行
    private func checkSingleInstance() -> Bool {
        // 首先检查并清理僵尸锁文件
        cleanupZombieLockFile()
        
        // 尝试获取文件锁
        if !acquireLockFile() {
            // 如果无法获取文件锁，再次检查是否为僵尸锁文件
            if isZombieLockFile() {
                print("检测到僵尸锁文件，正在清理...")
                forceCleanupLockFile()
                // 清理后重新尝试获取锁
                if acquireLockFile() {
                    return true
                }
            }
            
            // 确实有其他实例在运行，激活它
            activateExistingInstance()
            return false
        }
        
        // 双重检查：通过运行应用程序列表验证
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.paiste.app"
        let runningApps = NSWorkspace.shared.runningApplications
        
        let instanceCount = runningApps.filter { app in
            app.bundleIdentifier == bundleIdentifier
        }.count
        
        if instanceCount > 1 {
            // 如果发现多个实例，释放锁文件并激活已存在的实例
            releaseLockFile()
            activateExistingInstance()
            return false
        }
        
        return true
    }
    
    // 获取文件锁
    private func acquireLockFile() -> Bool {
        let fileManager = FileManager.default
        
        // 如果锁文件不存在，创建它
        if !fileManager.fileExists(atPath: lockFilePath) {
            fileManager.createFile(atPath: lockFilePath, contents: Data(), attributes: nil)
        }
        
        do {
            lockFileHandle = try FileHandle(forWritingTo: URL(fileURLWithPath: lockFilePath))
            
            // 尝试获取独占锁
            let result = flock(lockFileHandle!.fileDescriptor, LOCK_EX | LOCK_NB)
            if result == 0 {
                // 成功获取锁，写入当前进程ID和启动时间戳
                let currentProcessId = ProcessInfo.processInfo.processIdentifier
                let startTime = getCurrentProcessStartTime() ?? Date().timeIntervalSince1970
                let processInfo = "\(currentProcessId):\(startTime)\n"
                lockFileHandle?.write(processInfo.data(using: .utf8) ?? Data())
                return true
            } else {
                // 无法获取锁
                lockFileHandle?.closeFile()
                lockFileHandle = nil
                return false
            }
        } catch {
            print("无法打开锁文件: \(error)")
            return false
        }
    }
    
    // 释放文件锁
    private func releaseLockFile() {
        if let handle = lockFileHandle {
            flock(handle.fileDescriptor, LOCK_UN)
            handle.closeFile()
            lockFileHandle = nil
        }
        
        // 删除锁文件
        try? FileManager.default.removeItem(atPath: lockFilePath)
    }
    
    // 激活已存在的实例
    private func activateExistingInstance() {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.paiste.app"
        let runningApps = NSWorkspace.shared.runningApplications
        
        for app in runningApps {
            if app.bundleIdentifier == bundleIdentifier && app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                app.activate(options: [.activateIgnoringOtherApps])
                break
            }
        }
    }
    
    // 检查并清理僵尸锁文件
    private func cleanupZombieLockFile() {
        guard FileManager.default.fileExists(atPath: lockFilePath) else { return }
        
        if isZombieLockFile() {
            print("发现僵尸锁文件，正在清理...")
            forceCleanupLockFile()
        }
    }
    
    // 检查是否为僵尸锁文件（锁文件存在但对应进程不存在）
    private func isZombieLockFile() -> Bool {
        guard FileManager.default.fileExists(atPath: lockFilePath) else { return false }
        
        // 读取锁文件内容（格式：进程ID:启动时间戳）
        guard let lockContent = try? String(contentsOfFile: lockFilePath, encoding: .utf8) else {
            // 如果无法读取锁文件，认为是无效的锁文件
            return true
        }
        
        let components = lockContent.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: ":")
        
        // 兼容旧格式（只有进程ID）和新格式（进程ID:时间戳）
        guard let processId = Int32(components[0]) else {
            // 如果无法解析进程ID，认为是无效的锁文件
            return true
        }
        
        // 检查进程是否仍在运行
        let result = kill(processId, 0) // 发送信号0检查进程是否存在
        if result == 0 {
            // 进程存在，进行更严格的验证
            if components.count >= 2, let lockTimestamp = TimeInterval(components[1]) {
                // 新格式：检查进程ID和启动时间
                return !isValidPaisteProcessWithTimestamp(processId: processId, expectedStartTime: lockTimestamp)
            } else {
                // 旧格式：只检查进程ID和bundle identifier
                return !isValidPaisteProcess(processId: processId)
            }
        } else {
            // 进程不存在，是僵尸锁文件
            return true
        }
    }
    
    // 检查指定进程ID是否为有效的Paiste进程
    private func isValidPaisteProcess(processId: Int32) -> Bool {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.paiste.app"
        let runningApps = NSWorkspace.shared.runningApplications
        
        for app in runningApps {
            if app.processIdentifier == processId && app.bundleIdentifier == bundleIdentifier {
                return true
            }
        }
        return false
    }
    
    // 检查指定进程ID和启动时间是否匹配有效的Paiste进程
    private func isValidPaisteProcessWithTimestamp(processId: Int32, expectedStartTime: TimeInterval) -> Bool {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.paiste.app"
        let runningApps = NSWorkspace.shared.runningApplications
        
        for app in runningApps {
            if app.processIdentifier == processId && app.bundleIdentifier == bundleIdentifier {
                // 获取进程的实际启动时间
                if let actualStartTime = getProcessStartTime(processId: processId) {
                    // 允许1秒的时间误差（考虑到系统时间精度）
                    let timeDifference = abs(actualStartTime - expectedStartTime)
                    return timeDifference < 1.0
                }
                // 如果无法获取启动时间，降级到基本检查
                return true
            }
        }
        return false
    }
    
    // 获取进程的启动时间
    private func getProcessStartTime(processId: Int32) -> TimeInterval? {
        var kinfo = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, processId]
        
        let result = sysctl(&mib, u_int(mib.count), &kinfo, &size, nil, 0)
        
        if result == 0 {
            let startTime = kinfo.kp_proc.p_starttime
            let seconds = Double(startTime.tv_sec) + Double(startTime.tv_usec) / 1_000_000.0
            return seconds
        }
        
        return nil
    }
    
    // 获取当前进程的启动时间
    private func getCurrentProcessStartTime() -> TimeInterval? {
        return getProcessStartTime(processId: ProcessInfo.processInfo.processIdentifier)
    }
    
    // 强制清理锁文件
    private func forceCleanupLockFile() {
        do {
            try FileManager.default.removeItem(atPath: lockFilePath)
            print("僵尸锁文件已清理: \(lockFilePath)")
        } catch {
            print("清理锁文件失败: \(error)")
        }
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
        
        // 设置appDelegate引用，用于失焦检测
        window.appDelegate = self
        
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
        
        // 启动失焦监听
        window.startFocusMonitoring()
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
    
    func hideClipboardWindow(restoreFocus: Bool = true) {
        guard let window = clipboardWindow else { return }
        
        // 停止失焦监听
        window.stopFocusMonitoring()
        
        // 从底部隐藏的实现
        hideToBottom(window: window)
        
        // 根据参数决定是否恢复之前活跃应用程序的焦点
        if restoreFocus {
            restorePreviousAppFocus()
        } else {
            // 清除记录的应用程序引用，但不激活
            previousActiveApp = nil
        }
    }
    
    // 清除之前的应用引用（用于桌面切换等场景）
    func clearPreviousApp() {
        previousActiveApp = nil
    }
    
    private func restorePreviousAppFocus() {
        // 使用较短的延迟确保窗口关闭动画完成，提升用户体验
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
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
    
    // 从底部隐藏的实现（优化版本，更快的关闭速度）
    private func hideToBottom(window: ClipboardWindow) {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let currentFrame = window.frame
        
        // 计算滑出目标位置（屏幕底部下方）
        let targetY = screenFrame.minY - currentFrame.height - 20
        let targetFrame = NSRect(x: currentFrame.minX, y: targetY, width: currentFrame.width, height: currentFrame.height)
        
        // 超快速隐藏动画，提升用户体验
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.05  // 进一步减少动画时间到0.05秒
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)  // 使用easeIn获得更快的开始
            window.animator().alphaValue = 0.0
            window.animator().setFrame(targetFrame, display: true)
        }) { [weak self] in
            // 简化的完成回调
            guard let self = self, let window = self.clipboardWindow else { return }
            window.orderOut(nil)
            window.alphaValue = 1.0
            // 不需要复杂的位置重置，因为下次显示时会重新计算
        }
    }
}
