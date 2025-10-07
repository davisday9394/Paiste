import SwiftUI
import Combine

// 剪贴板内容类型
enum ClipboardCategory: String, CaseIterable {
    case all
    case text
    case image
    case file
    
    var displayName: String {
        switch self {
        case .all: return "全部内容"
        case .text: return "文本"
        case .image: return "图片"
        case .file: return "文件"
        }
    }
    
    var iconName: String {
        switch self {
        case .all: return "clipboard"
        case .text: return "doc.text"
        case .image: return "photo"
        case .file: return "folder"
        }
    }
}

// 剪贴板内容
enum ClipboardContent {
    case text(String)
    case image(NSImage)
    case file(URL)
}

// 剪贴板项目
class ClipboardItem: Identifiable {
    let id = UUID()
    let content: ClipboardContent
    let date: Date
    let type: ClipboardCategory
    
    init(content: ClipboardContent, type: ClipboardCategory) {
        self.content = content
        self.date = Date()
        self.type = type
    }
    
    var dateFormatted: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    func paste() {
        switch content {
        case .text(let text):
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            
        case .image(let image):
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([image])
            
        case .file(let url):
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([url as NSURL])
        }
    }
}

// 剪贴板管理器
class ClipboardManager: ObservableObject {
    static let shared = ClipboardManager()
    
    @Published var items: [ClipboardItem] = []
    private var cancellables = Set<AnyCancellable>()
    private var timer: Timer?
    private var lastChangeCount: Int = 0
    
    private init() {
        // 添加一些示例数据
        addSampleItems()
    }
    
    func copyItemToPasteboard(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        switch item.content {
        case .text(let text):
            pasteboard.setString(text, forType: .string)
        case .image(let image):
            pasteboard.writeObjects([image])
        case .file(let url):
            pasteboard.writeObjects([url as NSURL])
        }
    }
    
    func moveItemToTop(_ item: ClipboardItem) {
        DispatchQueue.main.async {
            if let index = self.items.firstIndex(where: { $0.id == item.id }) {
                let movedItem = self.items.remove(at: index)
                self.items.insert(movedItem, at: 0)
            }
        }
    }
    
    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkForPasteboardChanges()
        }
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
    
    private func checkForPasteboardChanges() {
        let pasteboard = NSPasteboard.general
        if pasteboard.changeCount != lastChangeCount {
            lastChangeCount = pasteboard.changeCount
            
            if let string = pasteboard.string(forType: .string) {
                let item = ClipboardItem(content: .text(string), type: .text)
                addItem(item)
            } else if let image = pasteboard.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage {
                let item = ClipboardItem(content: .image(image), type: .image)
                addItem(item)
            } else if let url = pasteboard.readObjects(forClasses: [NSURL.self], options: nil)?.first as? URL {
                let item = ClipboardItem(content: .file(url), type: .file)
                addItem(item)
            }
        }
    }
    
    func addItem(_ item: ClipboardItem) {
        DispatchQueue.main.async {
            // 检查是否已存在相同内容的项目
            let isDuplicate = self.items.contains { existingItem in
                switch (existingItem.content, item.content) {
                case (.text(let existingText), .text(let newText)):
                    return existingText == newText
                case (.image, .image):
                    return true // 简单处理，认为所有图片都是重复的
                case (.file(let existingURL), .file(let newURL)):
                    return existingURL.path == newURL.path
                default:
                    return false
                }
            }
            
            // 如果不是重复项，才添加到列表
            if !isDuplicate {
                // 添加到列表开头
                self.items.insert(item, at: 0)
                
                // 限制存储数量
                if self.items.count > 100 {
                    self.items.removeLast()
                }
            }
        }
    }
    
    private func addSampleItems() {
        // 添加示例文本
        let textItem1 = ClipboardItem(
            content: .text("工作与生活平衡\n新的见解"),
            type: .text
        )
        
        let textItem2 = ClipboardItem(
            content: .text("Blue Bottle Coffee\n123 Main St\nSan Francisco, CA"),
            type: .text
        )
        
        let textItem3 = ClipboardItem(
            content: .text("#5E6AD2"),
            type: .text
        )
        
        let textItem4 = ClipboardItem(
            content: .text("Jordan Gordon\nArt Director\ngordon@studio13\nDesigner"),
            type: .text
        )
        
        // 添加真实图片示例
        // 创建一个简单的彩色图片
        let imageSize = NSSize(width: 300, height: 200)
        let image = NSImage(size: imageSize)
        
        image.lockFocus()
        // 绘制渐变背景
        let gradient = NSGradient(colors: [NSColor.blue, NSColor.purple])
        gradient?.draw(in: NSRect(origin: .zero, size: imageSize), angle: 45)
        
        // 绘制一些简单的形状
        NSColor.white.setFill()
        let circlePath = NSBezierPath(ovalIn: NSRect(x: 50, y: 50, width: 100, height: 100))
        circlePath.fill()
        
        NSColor.yellow.setFill()
        let rectanglePath = NSBezierPath(rect: NSRect(x: 180, y: 70, width: 80, height: 60))
        rectanglePath.fill()
        
        // 添加文字
        let text = "示例图片"
        let font = NSFont.boldSystemFont(ofSize: 24)
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        
        let textSize = text.size(withAttributes: textAttributes)
        let textPoint = NSPoint(x: (imageSize.width - textSize.width) / 2, y: 20)
        text.draw(at: textPoint, withAttributes: textAttributes)
        
        image.unlockFocus()
        
        let imageItem = ClipboardItem(
            content: .image(image),
            type: .image
        )
        items.append(imageItem)
        
        // 再添加一个不同的图片
        let image2 = NSImage(size: imageSize)
        image2.lockFocus()
        
        // 绘制不同的渐变背景
        let gradient2 = NSGradient(colors: [NSColor.green, NSColor.orange])
        gradient2?.draw(in: NSRect(origin: .zero, size: imageSize), angle: 135)
        
        // 绘制不同的形状
        NSColor.red.setFill()
        let starPath = NSBezierPath()
        let center = NSPoint(x: imageSize.width / 2, y: imageSize.height / 2)
        let outerRadius: CGFloat = 80
        let innerRadius: CGFloat = 40
        let points = 5
        
        for i in 0..<points * 2 {
            let radius = i % 2 == 0 ? outerRadius : innerRadius
            let angle = CGFloat(i) * .pi / CGFloat(points)
            let x = center.x + radius * sin(angle)
            let y = center.y + radius * cos(angle)
            
            if i == 0 {
                starPath.move(to: NSPoint(x: x, y: y))
            } else {
                starPath.line(to: NSPoint(x: x, y: y))
            }
        }
        starPath.close()
        starPath.fill()
        
        image2.unlockFocus()
        
        let imageItem2 = ClipboardItem(
            content: .image(image2),
            type: .image
        )
        items.append(imageItem2)
        
        // 添加示例文件
        if let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let fileItem = ClipboardItem(
                content: .file(documentsURL),
                type: .file
            )
            items.append(fileItem)
        }
        
        // 添加示例项目
        items.append(contentsOf: [textItem1, textItem2, textItem3, textItem4])
    }
}