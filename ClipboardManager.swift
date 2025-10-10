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
class ClipboardItem: Identifiable, Codable {
    let id: UUID
    let content: ClipboardContent
    let date: Date
    let type: ClipboardCategory
    
    init(content: ClipboardContent, type: ClipboardCategory) {
        self.id = UUID()
        self.content = content
        self.date = Date()
        self.type = type
    }
    
    // 用于Codable的编码
    enum CodingKeys: String, CodingKey {
        case id, content, date, type
    }
    
    // 定义内容编码所需的键
    enum ContentCodingKeys: String, CodingKey {
        case type, value
    }
    
    // 编码方法
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(date, forKey: .date)
        try container.encode(type.rawValue, forKey: .type)
        
        // 根据内容类型进行不同的编码
        var contentContainer = container.nestedContainer(keyedBy: ContentCodingKeys.self, forKey: .content)
        
        switch content {
        case .text(let text):
            try contentContainer.encode("text", forKey: .type)
            try contentContainer.encode(text, forKey: .value)
        case .image(let image):
            if let tiffData = image.tiffRepresentation {
                try contentContainer.encode("image", forKey: .type)
                try contentContainer.encode(tiffData, forKey: .value)
            }
        case .file(let url):
            try contentContainer.encode("file", forKey: .type)
            try contentContainer.encode(url.absoluteString, forKey: .value)
        }
    }
    
    // 解码方法
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        date = try container.decode(Date.self, forKey: .date)
        let typeString = try container.decode(String.self, forKey: .type)
        guard let decodedType = ClipboardCategory(rawValue: typeString) else {
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Invalid type")
        }
        type = decodedType
        
        // 解码内容
        let contentContainer = try container.nestedContainer(keyedBy: ContentCodingKeys.self, forKey: .content)
        let contentType = try contentContainer.decode(String.self, forKey: .type)
        
        // 定义内容解码所需的键
        enum ContentCodingKeys: String, CodingKey {
            case type, value
        }
        
        switch contentType {
        case "text":
            let text = try contentContainer.decode(String.self, forKey: .value)
            content = .text(text)
        case "image":
            let imageData = try contentContainer.decode(Data.self, forKey: .value)
            if let image = NSImage(data: imageData) {
                content = .image(image)
            } else {
                throw DecodingError.dataCorruptedError(forKey: .value, in: contentContainer, debugDescription: "Invalid image data")
            }
        case "file":
            let urlString = try contentContainer.decode(String.self, forKey: .value)
            if let url = URL(string: urlString) {
                content = .file(url)
            } else {
                throw DecodingError.dataCorruptedError(forKey: .value, in: contentContainer, debugDescription: "Invalid URL string")
            }
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: contentContainer, debugDescription: "Unknown content type")
        }
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

class ClipboardManager: ObservableObject {
    static let shared = ClipboardManager()
    
    @Published var items: [ClipboardItem] = []
    private var cancellables = Set<AnyCancellable>()
    private var timer: Timer?
    private var lastChangeCount: Int = 0
    
    // 最大存储项目数
    private let maxStoredItems = 100
    
    // 存储URL
    private var storageURL: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("clipboard_history.json")
    }
    
    private init() {
        // 从文件加载数据
        loadItems()
        
        // 如果没有加载到数据，添加一些示例数据
        if items.isEmpty {
            self.addSampleItems()
        }
        
        // 设置定时器监控剪贴板变化
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkForPasteboardChanges()
        }
    }
    
    // 保存数据到文件
    private func saveItems() {
        // 创建可存储的数据结构
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        
        do {
            // 最多只保存maxStoredItems个项目
            let itemsToSave = Array(self.items.prefix(maxStoredItems))
            let data = try encoder.encode(itemsToSave)
            try data.write(to: storageURL)
            print("成功保存\(itemsToSave.count)个剪贴板项目到文件")
        } catch {
            print("保存剪贴板历史失败: \(error.localizedDescription)")
        }
    }
    
    // 从文件加载数据
    private func loadItems() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            print("剪贴板历史文件不存在")
            return
        }
        
        do {
            let data = try Data(contentsOf: storageURL)
            let decoder = JSONDecoder()
            self.items = try decoder.decode([ClipboardItem].self, from: data)
            print("成功从文件加载\(items.count)个剪贴板项目")
        } catch {
            print("加载剪贴板历史失败: \(error.localizedDescription)")
            self.items = []
        }
    }
    
    private func checkForPasteboardChanges() {
        let pasteboard = NSPasteboard.general
        if pasteboard.changeCount != lastChangeCount {
            lastChangeCount = pasteboard.changeCount
            
            // 检查是否有新的文本
            if let text = pasteboard.string(forType: .string), !text.isEmpty {
                let item = ClipboardItem(content: .text(text), type: .text)
                self.addItem(item)
                return
            }
            
            // 检查是否有新的图片
            if let image = readPasteboardImage() {
                let item = ClipboardItem(content: .image(image), type: .image)
                self.addItem(item)
                return
            }
            
            // 检查是否有新的文件
            if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
                let item = ClipboardItem(content: .file(urls[0]), type: .file)
                self.addItem(item)
                return
            }
        }
    }
    
    // 从剪贴板读取图片的多种方法
    private func readPasteboardImage() -> NSImage? {
        let pasteboard = NSPasteboard.general
        
        // 方法1: 直接使用NSImage初始化
        if let image = NSImage(pasteboard: pasteboard) {
            print("DEBUG: 成功通过NSImage(pasteboard:)读取图片")
            return image
        }
        
        // 方法2: 读取TIFF数据
        if let tiffData = pasteboard.data(forType: .tiff), let image = NSImage(data: tiffData) {
            print("DEBUG: 成功通过TIFF数据读取图片")
            return image
        }
        
        // 方法3: 读取PNG数据
        if let pngData = pasteboard.data(forType: .png), let image = NSImage(data: pngData) {
            print("DEBUG: 成功通过PNG数据读取图片")
            return image
        }
        
        // 方法4: 尝试读取其他图片类型
        let imageTypes = [
            NSPasteboard.PasteboardType("public.jpeg"),
            NSPasteboard.PasteboardType("public.gif"),
            NSPasteboard.PasteboardType("com.apple.pict")
        ]
        
        for type in imageTypes {
            if let data = pasteboard.data(forType: type), let image = NSImage(data: data) {
                print("DEBUG: 成功通过\(type.rawValue)类型读取图片")
                return image
            }
        }
        
        // 方法5: 尝试从文件URL读取图片
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
            let url = urls[0]
            if let image = NSImage(contentsOf: url) {
                print("DEBUG: 成功从URL读取图片: \(url.path)")
                return image
            }
        }
        
        print("DEBUG: 无法从剪贴板读取图片，可用类型: \(pasteboard.types?.map { $0.rawValue } ?? [])")
        return nil
    }
    
    // 复制项目到剪贴板
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
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let index = self.items.firstIndex(where: { $0.id == item.id }) {
                let movedItem = self.items.remove(at: index)
                self.items.insert(movedItem, at: 0)
                
                // 保存数据到文件
                self.saveItems()
            }
        }
    }
    
    func moveItemToTop(at index: Int) {
        if index >= 0 && index < items.count {
            let item = items[index]
            moveItemToTop(item)
        }
    }
    
    func removeItem(at index: Int) {
        if index >= 0 && index < items.count {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.items.remove(at: index)
                
                // 保存数据到文件
                self.saveItems()
            }
        }
    }
    
    func removeItem(_ item: ClipboardItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            removeItem(at: index)
        }
    }
    
    func clearItems() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.items.removeAll()
            
            // 保存数据到文件
            self.saveItems()
        }
    }
    
    // 比较两个内容是否相同
    private func isSameContent(_ content1: ClipboardContent, _ content2: ClipboardContent) -> Bool {
        switch (content1, content2) {
        case (.text(let text1), .text(let text2)):
            return text1 == text2
        case (.image, .image):
            return true // 简单处理，认为所有图片都是重复的
        case (.file(let url1), .file(let url2)):
            return url1.path == url2.path
        default:
            return false
        }
    }
    
    func addItem(_ item: ClipboardItem) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 检查是否已存在相同内容
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
                
                // 保存数据到文件
                self.saveItems()
            }
        }
    }
    
    private func addSampleItems() {
        // 添加示例文本
        let textItem = ClipboardItem(content: .text("这是一个示例文本"), type: .text)
        self.items.append(textItem)
        
        // 保存数据到文件
        self.saveItems()
    }
}
