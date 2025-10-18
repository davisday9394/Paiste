import SwiftUI
import Combine

// 剪贴板内容类型
enum ClipboardCategory: String, CaseIterable {
    case all
    case text
    
    var displayName: String {
        switch self {
        case .all: return "全部内容"
        case .text: return "文本"
        }
    }
    
    var iconName: String {
        switch self {
        case .all: return "clipboard"
        case .text: return "doc.text"
        }
    }
}

// 剪贴板内容
enum ClipboardContent {
    case text(String)
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
        
        // 编码文本内容
        var contentContainer = container.nestedContainer(keyedBy: ContentCodingKeys.self, forKey: .content)
        
        switch content {
        case .text(let text):
            try contentContainer.encode("text", forKey: .type)
            try contentContainer.encode(text, forKey: .value)
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
        
        switch contentType {
        case "text":
            let text = try contentContainer.decode(String.self, forKey: .value)
            content = .text(text)
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
        
        // 调试输出：显示当前剪切板历史内容
        print("DEBUG: ClipboardManager初始化完成，当前有 \(items.count) 个项目")
        for (index, item) in items.enumerated() {
            switch item.content {
            case .text(let text):
                print("DEBUG: 项目 \(index): 文本 - \(text.prefix(50))...")
            }
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
            NSLog("DEBUG: 剪切板变化检测到，changeCount: %d -> %d", lastChangeCount, pasteboard.changeCount)
            lastChangeCount = pasteboard.changeCount
            
            // 检查是否有新的文本
            if let text = pasteboard.string(forType: .string), !text.isEmpty {
                NSLog("DEBUG: 检测到文本内容: %@", String(text.prefix(50)))
                let item = ClipboardItem(content: .text(text), type: .text)
                self.addItem(item)
                return
            }
            
            NSLog("DEBUG: 剪切板变化但未检测到有效内容")
        }
    }
    
    // 复制项目到剪贴板
    func copyItemToPasteboard(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        switch item.content {
        case .text(let text):
            pasteboard.setString(text, forType: .string)
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
        }
    }
    
    func addItem(_ item: ClipboardItem) {
        NSLog("DEBUG: addItem被调用，内容类型: \(item.type)")
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 检查是否已存在相同内容
            var duplicateIndex: Int? = nil
            for (index, existingItem) in self.items.enumerated() {
                switch (existingItem.content, item.content) {
                case (.text(let existingText), .text(let newText)):
                    if existingText == newText {
                        duplicateIndex = index
                        break
                    }
                default:
                    continue
                }
            }
            
            if let duplicateIndex = duplicateIndex {
                // 如果找到重复项，将其移到顶部
                NSLog("DEBUG: 找到重复项目在索引 \(duplicateIndex)，移动到顶部")
                let duplicateItem = self.items.remove(at: duplicateIndex)
                self.items.insert(duplicateItem, at: 0)
                NSLog("DEBUG: 重复项目已移动到顶部")
            } else {
                // 如果不是重复项，添加到列表
                NSLog("DEBUG: 添加新项目到列表，当前列表长度: \(self.items.count)")
                self.items.insert(item, at: 0)
                NSLog("DEBUG: 项目已添加，新列表长度: \(self.items.count)")
                
                // 限制存储数量
                if self.items.count > 100 {
                    self.items.removeLast()
                }
            }
            
            // 保存数据到文件
            self.saveItems()
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
