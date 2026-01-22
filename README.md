# dyTool

抖音视频批量下载工具 - macOS 原生应用

## 功能特性

- **用户管理** - 添加、编辑、删除抖音用户，支持批量管理
- **批量下载** - 支持串行/并发下载多个用户的视频
- **多种模式** - 支持下载主页作品、点赞、收藏、合集等
- **视频浏览** - 本地视频浏览和管理
- **菜单栏常驻** - 关闭窗口后可在菜单栏继续运行

## 下载模式

| 模式 | 说明 |
|------|------|
| post | 用户发布的作品 |
| like | 用户点赞的作品 |
| collection | 用户收藏的作品 |
| collects | 收藏夹内的作品 |
| mix | 合集内的作品 |
| music | 用户收藏的音乐 |

## 系统要求

- macOS 26.1 或更高版本
- Apple Silicon (arm64) 架构

## 使用说明

### 1. 配置 Cookie

首次使用需要配置抖音 Cookie：

1. 使用浏览器登录抖音网页版
2. 按 F12 打开开发者工具
3. 在 Network 标签页中找到任意请求
4. 复制请求头中的 Cookie 值
5. 在 dyTool 设置中粘贴 Cookie

### 2. 添加用户

1. 点击「用户管理」页面的添加按钮
2. 粘贴抖音用户主页 URL
3. 选择下载模式和数量限制
4. 保存用户信息

### 3. 开始下载

1. 在「下载任务」页面选择要下载的用户
2. 点击「开始下载」
3. 下载进度和日志会实时显示

## 项目结构

```
dyTool/
├── dyTool/                  # 主应用代码
│   ├── dyToolApp.swift      # 应用入口
│   ├── Views/               # 视图层
│   │   ├── MainView.swift
│   │   ├── DownloadView.swift
│   │   ├── SettingsView.swift
│   │   ├── VideoGalleryView.swift
│   │   ├── AnalysisView.swift
│   │   └── MenuBarView.swift
│   ├── Services/            # 服务层
│   │   ├── F2Service.swift
│   │   ├── DatabaseService.swift
│   │   ├── DownloadState.swift
│   │   └── AnalysisService.swift
│   ├── Models/              # 数据模型
│   │   ├── Models.swift
│   │   └── VideoAnalysis.swift
│   └── Resources/           # 资源文件
│       └── f2-cli           # f2 命令行工具
├── dyTool.xcodeproj/        # Xcode 项目文件
├── docs/                    # 文档
│   └── changelog/           # 变更记录
└── logs/                    # 运行日志
```

## 核心依赖

本项目依赖 [f2](https://github.com/JoeanAmier/f2) 项目提供的命令行工具进行视频下载。

## 开发

详见 [BUILD.md](docs/BUILD.md) 了解如何构建和打包应用。

## License

MIT License
