import Cocoa
import Carbon

class GlobalShortcutManager {
    private var eventHandler: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var shortcutHandler: (() -> Void)?
    
    deinit {
        unregister()
    }
    
    func register(keyCode: Int, modifiers: Int, handler: @escaping () -> Void) {
        // 保存回调
        shortcutHandler = handler
        
        // 创建事件类型规范
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )
        
        // 安装事件处理程序
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData = userData else { return noErr }
                let manager = Unmanaged<GlobalShortcutManager>.fromOpaque(userData).takeUnretainedValue()
                manager.shortcutHandler?()
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        
        // 注册热键
        var hotKeyID = EventHotKeyID(signature: OSType(0x50414953), // "PAIS"
                                    id: 1)
        
        let result = RegisterEventHotKey(
            UInt32(keyCode),
            UInt32(modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        
        if result != noErr {
            print("Failed to register hotkey: \(result)")
        }
    }
    
    func unregister() {
        if let eventHandler = eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        
        shortcutHandler = nil
    }
}

// 快捷键常量
enum KeyCode {
    static let v: Int = 9
}

enum KeyModifier {
    static let command: Int = 1 << 8
    static let shift: Int = 1 << 9
    static let option: Int = 1 << 11
    static let control: Int = 1 << 12
}