import SwiftUI

struct ClipboardView: View {
    @State private var searchText = ""
    @State private var selectedCategory: ClipboardCategory = .all
    @ObservedObject private var clipboardManager = ClipboardManager.shared
    
    @State private var selectedItemIndex: Int = 0
    @State private var scrollViewProxy: ScrollViewProxy? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            // 上方第一栏：搜索和分类
            HStack(spacing: 20) {
                Spacer()
                
                // 搜索输入框
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    
                    TextField("搜索", text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .frame(width: 200)
                
                // 分类标签栏
                HStack(spacing: 12) {
                    ForEach(ClipboardCategory.allCases, id: \.self) { category in
                        CategoryButton(
                            title: category.displayName,
                            systemImage: category.iconName,
                            isSelected: selectedCategory == category
                        ) {
                            selectedCategory = category
                            selectedItemIndex = 0 // 切换分类时重置选中项
                        }
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // 下方第二栏：剪贴板内容预览区
            VStack {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHGrid(rows: [GridItem(.fixed(150))], spacing: 16) {
                            ForEach(Array(filteredClipboardItems.enumerated()), id: \.element.id) { index, item in
                                ClipboardItemView(item: item)
                                    .id(item.id) // 为每个项目设置ID，用于滚动定位
                                    .frame(width: 200)
                                    .background(index == selectedItemIndex ? Color.blue.opacity(0.2) : Color.clear)
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(index == selectedItemIndex ? Color.blue : Color.clear, lineWidth: 2)
                                    )
                                    .onTapGesture {
                                        selectedItemIndex = index
                                    }
                            }
                        }
                        .padding()
                    }
                    .onChange(of: selectedItemIndex) { newValue in
                        // 当选中项变化时，滚动到选中项
                        if !filteredClipboardItems.isEmpty && newValue < filteredClipboardItems.count {
                            withAnimation(.easeOut(duration: 0.1)) {
                                proxy.scrollTo(filteredClipboardItems[newValue].id, anchor: .center)
                            }
                        }
                    }
                    .onAppear {
                        scrollViewProxy = proxy
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: 500)
        .onAppear {
            clipboardManager.startMonitoring()
            // 默认选择第一个项目
            if !filteredClipboardItems.isEmpty {
                selectedItemIndex = 0
            }
        }
        .onKeyPress(.leftArrow) {
            if selectedItemIndex > 0 {
                selectedItemIndex -= 1
            }
            return .handled
        }
        .onKeyPress(.rightArrow) {
            if selectedItemIndex < filteredClipboardItems.count - 1 {
                selectedItemIndex += 1
            }
            return .handled
        }
        .onKeyPress(.return) {
            if !filteredClipboardItems.isEmpty && selectedItemIndex < filteredClipboardItems.count {
                let selectedItem = filteredClipboardItems[selectedItemIndex]
                clipboardManager.copyItemToPasteboard(selectedItem)
                
                // 将选中项移到第一位
                clipboardManager.moveItemToTop(selectedItem)
                
                // 关闭弹窗
                if let window = NSApp.windows.first(where: { $0.isKeyWindow }) {
                    window.close()
                }
            }
            return .handled
        }
    }
    
    var filteredClipboardItems: [ClipboardItem] {
        var items = clipboardManager.items
        
        // 按类别过滤
        if selectedCategory != .all {
            items = items.filter { $0.type == selectedCategory }
        }
        
        // 按搜索文本过滤
        if !searchText.isEmpty {
            items = items.filter { item in
                if case .text(let text) = item.content {
                    return text.localizedCaseInsensitiveContains(searchText)
                }
                return false
            }
        }
        
        return items
    }
}

struct CategoryButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(title)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(isSelected ? Color.accentColor : Color.clear)
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(16)
            .contentShape(Rectangle()) // 确保整个区域都可点击
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ClipboardItemView: View {
    let item: ClipboardItem
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Image(systemName: item.type.iconName)
                    .foregroundColor(.gray)
                Text(item.type.displayName)
                    .font(.caption)
                    .foregroundColor(.gray)
                Spacer()
                Text(item.dateFormatted)
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            .padding(.bottom, 4)
            
            Spacer()
            
            // 内容预览
            Group {
                switch item.content {
                case .text(let text):
                    Text(text)
                        .lineLimit(5)
                case .image(let image):
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 100)
                        .cornerRadius(4)
                        .shadow(radius: 1)
                case .file(let url):
                    HStack {
                        Image(systemName: "doc")
                        Text(url.lastPathComponent)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor))
        .cornerRadius(8)
        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
        .onTapGesture {
            item.paste()
        }
    }
}

struct ClipboardView_Previews: PreviewProvider {
    static var previews: some View {
        ClipboardView()
    }
}
