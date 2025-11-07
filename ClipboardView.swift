import SwiftUI

struct ClipboardView: View {
    @State private var searchText = ""
    @State private var selectedCategory: ClipboardCategory = .all
    @ObservedObject private var clipboardManager = ClipboardManager.shared
    @ObservedObject private var appDelegate = AppDelegate.shared!
    
    @State private var selectedItemIndex: Int = 0
    @State private var scrollViewProxy: ScrollViewProxy? = nil
    @State private var showingClearConfirmation = false
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部工具栏 - 搜索框和分类按钮在同一行居中显示
            HStack(spacing: 16) {
                // 左侧占位
                Spacer()
                
                // 中间区域：搜索框和分类按钮
                HStack(spacing: 16) {
                    // 搜索框
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                            .font(.system(size: 14))
                        
                        TextField("搜索剪切板", text: $searchText)
                            .textFieldStyle(PlainTextFieldStyle())
                            .font(.system(size: 14))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
                    .cornerRadius(20)
                    .frame(width: 200)
                    
                    // 分类标签栏
                    HStack(spacing: 8) {
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
                }
                
                // 右侧占位和清空按钮
                Spacer()
                
                // 清空按钮
                Button(action: {
                    showingClearConfirmation = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.system(size: 12, weight: .medium))
                        Text("清空所有")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.red.opacity(0.1))
                    )
                    .foregroundColor(.red)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(clipboardManager.items.isEmpty)
                .opacity(clipboardManager.items.isEmpty ? 0.5 : 1.0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
            )
            
            // 剪贴板内容预览区
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 12) {
                            ForEach(Array(filteredClipboardItems.enumerated()), id: \.element.id) { index, item in
                                ClipboardItemView(item: item, isSelected: index == selectedItemIndex)
                                    .id(item.id)
                                    .frame(width: 220, height: 180)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(index == selectedItemIndex ? Color.accentColor.opacity(0.1) : Color.clear)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(index == selectedItemIndex ? Color.accentColor : Color.clear, lineWidth: 2)
                                    )
                                    .scaleEffect(index == selectedItemIndex ? 1.05 : 1.0)
                                    .animation(.easeInOut(duration: 0.12), value: index == selectedItemIndex)
                                    .onTapGesture {
                                        selectedItemIndex = index
                                    }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                    }
                    .onChange(of: selectedItemIndex) { newValue in
                        // 当选中项变化时，滚动到选中项
                        if !filteredClipboardItems.isEmpty && newValue < filteredClipboardItems.count {
                            proxy.scrollTo(filteredClipboardItems[newValue].id, anchor: .center)
                        }
                    }
                    .onAppear {
                        scrollViewProxy = proxy
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
        )
        .onAppear {
            // 每次显示时都重置到第一个项目
            selectedItemIndex = 0
        }
        .onChange(of: searchText) { _ in
            // 搜索文本变化时重置选中索引
            selectedItemIndex = 0
        }
        .onChange(of: appDelegate.resetSelectionTrigger) { _ in
            // 当窗口显示时重置选中索引
            selectedItemIndex = 0
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
            handleReturnKeyPress()
            return .handled
        }
        .alert("确认清空", isPresented: $showingClearConfirmation) {
            Button("取消", role: .cancel) { }
            Button("清空所有", role: .destructive) {
                clipboardManager.clearItems()
                selectedItemIndex = 0
            }
        } message: {
            Text("确定要清空所有剪切板历史吗？此操作无法撤销。")
        }
    }
    
    private func handleReturnKeyPress() {
        guard !filteredClipboardItems.isEmpty && selectedItemIndex < filteredClipboardItems.count else { return }
        
        let selectedItem = filteredClipboardItems[selectedItemIndex]
        
        // 立即复制到剪贴板
        clipboardManager.copyItemToPasteboard(selectedItem)
        
        // 立即关闭窗口，提升响应速度
        if let appDelegate = AppDelegate.shared {
            appDelegate.hideClipboardWindow()
        }
        
        // 在后台异步处理数据重排，避免阻塞UI
        DispatchQueue.main.async {
            clipboardManager.moveItemToTop(selectedItem)
        }
    }
    
    var filteredClipboardItems: [ClipboardItem] {
        var items = clipboardManager.items
        
        print("DEBUG: ClipboardView - 原始项目数量: \(items.count)")
        print("DEBUG: ClipboardView - 当前分类: \(selectedCategory)")
        print("DEBUG: ClipboardView - 搜索文本: '\(searchText)'")
        
        // 按类别过滤
        if selectedCategory != .all {
            items = items.filter { $0.type == selectedCategory }
            print("DEBUG: ClipboardView - 按分类过滤后项目数量: \(items.count)")
        }
        
        // 按搜索文本过滤
        if !searchText.isEmpty {
            items = items.filter { item in
                switch item.content {
                case .text(let text):
                    return text.localizedCaseInsensitiveContains(searchText)
                }
            }
            print("DEBUG: ClipboardView - 按搜索过滤后项目数量: \(items.count)")
        }
        
        print("DEBUG: ClipboardView - 最终显示项目数量: \(items.count)")
        for (index, item) in items.enumerated() {
            switch item.content {
            case .text(let text):
                print("DEBUG: ClipboardView - 项目 \(index): 文本 - \(text.prefix(30))...")
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
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .medium))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.1))
            )
            .foregroundColor(isSelected ? .white : .primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

struct ClipboardItemView: View {
    let item: ClipboardItem
    let isSelected: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 顶部信息栏
            HStack {
                Image(systemName: item.type.iconName)
                    .foregroundColor(.secondary)
                    .font(.system(size: 13, weight: .medium))
                Text(item.type.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Text(item.dateFormatted)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            // 内容预览
            Group {
                switch item.content {
                case .text(let text):
                    Text(text)
                        .font(.system(size: 15, weight: isSelected ? .medium : .regular))
                        .foregroundColor(.primary)
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
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
