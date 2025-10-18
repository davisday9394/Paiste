# Paiste - 高效的macOS文本剪贴板管理工具

Paiste是一个轻量级、高效的macOS文本剪贴板管理工具，专注于文本内容的记录和管理，帮助您提高工作效率。

## 主要功能

- **文本内容支持**：专注于文本内容的复制和粘贴管理
- **状态栏快速访问**：通过状态栏图标快速访问剪贴板历史
- **全局快捷键**：使用`Cmd+Shift+V`快速调用剪贴板面板
- **内容分类**：按类型（全部、文本）筛选剪贴板内容
- **搜索功能**：快速搜索文本内容
- **键盘导航**：使用方向键在剪贴板项目间快速切换
- **自动去重**：自动检测并去除重复的文本内容
- **轻量高效**：专注文本处理，性能优异，资源占用低

## 使用方法

1. **启动应用**：启动Paiste后，它会在状态栏显示一个图标
2. **访问剪贴板**：点击状态栏图标或使用快捷键`Cmd+Shift+V`打开剪贴板面板
3. **浏览内容**：使用左右方向键在剪贴板项目间切换
4. **粘贴内容**：选中项目后按回车键(Return)将内容复制到系统剪贴板并关闭面板
5. **筛选内容**：点击上方的分类按钮筛选不同类型的内容
6. **搜索内容**：在搜索框中输入关键词搜索文本内容

## 安装说明

### 从源码构建

1. 确保您的系统安装了Xcode 13.0或更高版本
2. 克隆项目到本地：
   ```bash
   git clone <repository-url>
   cd Paiste
   ```
3. 使用Xcode打开项目：
   ```bash
   open Paiste.xcodeproj
   ```
4. 在Xcode中选择目标设备并点击运行按钮，或使用命令行构建：
   ```bash
   xcodebuild -project Paiste.xcodeproj -scheme Paiste -configuration Release build
   ```

## 系统要求

- macOS 11.0或更高版本
- Xcode 13.0或更高版本（仅开发时需要）
- 约5MB的磁盘空间

## 技术栈

- **开发语言**：Swift 5.5+
- **UI框架**：SwiftUI
- **最低部署目标**：macOS 11.0
- **依赖项**：无第三方依赖，纯原生Swift实现

## 项目结构

```
Paiste/
├── Paiste/
│   ├── PaisteApp.swift          # 应用程序入口
│   ├── ClipboardManager.swift   # 剪贴板管理核心逻辑
│   ├── ClipboardView.swift      # 主界面视图
│   ├── ClipboardItem.swift      # 剪贴板项目数据模型
│   └── Assets.xcassets/         # 应用资源文件
├── Paiste.xcodeproj/           # Xcode项目文件
└── README.md                   # 项目说明文档
```

## 开发信息

Paiste是一个专注于文本剪贴板管理的macOS应用，使用现代Swift和SwiftUI技术栈开发。项目采用MVVM架构模式，代码简洁易维护。

### 核心特性
- 实时监控系统剪贴板变化
- 本地文件持久化存储
- 高效的文本内容去重算法
- 响应式UI设计

## 隐私说明

Paiste严格保护用户隐私：
- 所有剪贴板内容仅在本地存储，不会发送到任何服务器
- 不收集任何用户数据或使用统计信息
- 应用退出后，剪贴板历史记录将被清除
- 不需要网络权限，完全离线运行

## 贡献指南

欢迎提交Issue和Pull Request来改进Paiste！

1. Fork本项目
2. 创建您的功能分支 (`git checkout -b feature/AmazingFeature`)
3. 提交您的更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 打开一个Pull Request

## 许可证

Copyright © 2023. 保留所有权利。

## 更新日志

### v1.0.0
- 初始版本发布
- 支持文本剪贴板管理
- 状态栏快速访问
- 全局快捷键支持
- 搜索和筛选功能