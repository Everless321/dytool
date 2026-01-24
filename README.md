# dyTool

抖音视频批量下载工具 - macOS 原生应用

基于 SwiftUI 构建，集成 [f2](https://github.com/JoeanAmier/f2) 命令行工具，提供图形化界面管理用户和下载任务。

## 功能特性

### 核心功能
- **用户管理** - 添加、编辑、删除抖音用户，支持批量设置下载参数
- **批量下载** - 支持串行/并发下载，智能用户选择（搜索、筛选、排序）
- **多种模式** - 主页作品、点赞、收藏、合集、音乐等下载模式
- **视频浏览** - 本地视频网格浏览，支持筛选和分页加载

### 分析功能
- **视频分析** - 基于 OpenAI Vision API 的视频内容分析
- **图集支持** - 自动识别和分析图集作品
- **智能采样** - 视频抽帧、图集均匀采样

### 用户体验
- **菜单栏常驻** - 关闭窗口后可在菜单栏继续运行
- **实时进度** - 下载进度、刷新进度实时显示
- **下载统计** - 按作品去重统计，支持视频和图集

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

- macOS 14.0 或更高版本
- Apple Silicon (arm64) 架构

## 快速开始

### 1. 配置 Cookie

首次使用需要配置抖音 Cookie：

1. 使用浏览器登录 [抖音网页版](https://www.douyin.com)
2. 按 F12 打开开发者工具 → Network 标签
3. 刷新页面，找到任意请求
4. 复制请求头中的 `Cookie` 值
5. 在 dyTool「设置」中粘贴 Cookie

### 2. 添加用户

1. 点击「用户管理」→ 添加按钮
2. 粘贴抖音用户主页 URL（支持自动解析剪贴板）
3. 选择下载模式和数量限制
4. 保存

### 3. 下载视频

1. 进入「下载任务」页面
2. 使用搜索/筛选选择用户（支持"选择未完成的"快捷操作）
3. 点击「开始下载」
4. 实时查看进度和日志

### 4. 视频分析（可选）

1. 在「设置」中配置 OpenAI API Key
2. 进入「视频分析」页面
3. 扫描待分析项目（视频+图集）
4. 开始分析，结果保存到数据库

## 项目结构

```
dyTool/
├── dyTool/                  # Swift 主应用
│   ├── Views/               # 视图层
│   │   ├── MainView.swift          # 主视图（导航布局）
│   │   ├── UserListView.swift      # 用户管理
│   │   ├── DownloadView.swift      # 下载任务
│   │   ├── VideoGalleryView.swift  # 视频浏览
│   │   ├── AnalysisView.swift      # 视频分析
│   │   ├── SettingsView.swift      # 设置
│   │   └── MenuBarView.swift       # 菜单栏
│   ├── Services/            # 服务层
│   │   ├── F2Service.swift         # f2-cli 封装
│   │   ├── DatabaseService.swift   # SQLite 存储
│   │   ├── DownloadState.swift     # 下载状态管理
│   │   ├── AnalysisService.swift   # 视频分析服务
│   │   └── BackendService.swift    # 后端 API 客户端
│   ├── Models/              # 数据模型
│   │   ├── Models.swift            # 用户、设置等模型
│   │   └── VideoAnalysis.swift     # 分析结果模型
│   └── Resources/
│       └── f2-cli           # f2 命令行工具
├── backend/                 # Python 后端（可选）
│   └── app/
│       ├── main.py          # FastAPI 入口
│       └── routers/
│           └── users.py     # 用户解析 API
├── dyTool.xcodeproj/        # Xcode 项目
├── docs/                    # 文档
│   └── changelog/           # 变更记录
└── logs/                    # 运行日志
```

## 架构说明

### 服务层（单例模式）

| 服务 | 职责 |
|------|------|
| `F2Service` | 封装 f2-cli，管理下载进程 |
| `DatabaseService` | SQLite 存储，发布状态变更 |
| `DownloadState` | 共享下载进度状态 |
| `AnalysisService` | 视频/图集内容分析 |
| `BackendService` | Python 后端 HTTP 客户端 |

### 数据流

```
Views ← @EnvironmentObject ← Services (.shared 单例)
                               ↓
                           SQLite DB
```

## 开发

### 构建应用

```bash
# Xcode 构建
xcodebuild -project dyTool.xcodeproj -scheme dyTool -configuration Debug build

# 或直接用 Xcode 打开
open dyTool.xcodeproj
```

### 运行后端（可选）

```bash
cd backend
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload
```

后端提供 `/api/users/parse` 接口用于解析用户信息。

## 核心依赖

- [f2](https://github.com/JoeanAmier/f2) - 抖音下载命令行工具
- [OpenAI API](https://platform.openai.com/) - 视频内容分析（可选）
- [FastAPI](https://fastapi.tiangolo.com/) - 后端框架（可选）

## License

MIT License
