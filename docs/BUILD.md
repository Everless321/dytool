# dyTool 构建指南

## 环境要求

- Xcode 26.1 或更高版本
- macOS 26.1 SDK
- Apple Developer 账号（用于签名）

## f2-cli 准备

dyTool 依赖 f2 项目的命令行工具进行视频下载。需要先准备 f2-cli 二进制文件。

### 方式一：从 f2 Release 下载（推荐）

1. 访问 [f2 Releases](https://github.com/JoeanAmier/f2/releases)
2. 下载最新的 macOS arm64 版本
3. 解压后重命名为 `f2-cli`
4. 放入 `dyTool/Resources/` 目录

### 方式二：从源码编译

f2 是一个 Python 项目，可以使用 PyInstaller 打包成独立可执行文件：

```bash
# 1. 克隆 f2 仓库
git clone https://github.com/JoeanAmier/f2.git
cd f2

# 2. 创建虚拟环境
python3 -m venv venv
source venv/bin/activate

# 3. 安装依赖
pip install -r requirements.txt
pip install pyinstaller

# 4. 打包为单文件可执行程序
pyinstaller --onefile --name f2-cli f2/__main__.py

# 5. 输出文件在 dist/f2-cli
```

### f2-cli 验证

确保 f2-cli 可以正常运行：

```bash
./f2-cli --version
# 输出: Version 0.0.1.7 或更高版本
```

### 放置位置

将 `f2-cli` 放入项目的 Resources 目录：

```
dyTool/
└── dyTool/
    └── Resources/
        └── f2-cli    # 放这里
```

## 构建应用

### 使用 Xcode

1. 打开 `dyTool.xcodeproj`
2. 选择目标设备 `My Mac`
3. 选择 `Product > Build` (⌘B) 构建
4. 选择 `Product > Archive` 打包发布版本

### 使用命令行

```bash
# 构建 Debug 版本
xcodebuild -project dyTool.xcodeproj \
           -scheme dyTool \
           -configuration Debug \
           build

# 构建 Release 版本
xcodebuild -project dyTool.xcodeproj \
           -scheme dyTool \
           -configuration Release \
           build
```

## 打包分发

### 创建 Archive

```bash
xcodebuild -project dyTool.xcodeproj \
           -scheme dyTool \
           -configuration Release \
           -archivePath build/dyTool.xcarchive \
           archive
```

### 导出 App

```bash
xcodebuild -exportArchive \
           -archivePath build/dyTool.xcarchive \
           -exportPath build/Export \
           -exportOptionsPlist ExportOptions.plist
```

### ExportOptions.plist 示例

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>D45DU5PR2Y</string>
</dict>
</plist>
```

## 项目配置说明

### 关键配置项

| 配置项 | 值 | 说明 |
|--------|-----|------|
| PRODUCT_BUNDLE_IDENTIFIER | net.everless.dyTool | 应用标识符 |
| MACOSX_DEPLOYMENT_TARGET | 26.1 | 最低支持版本 |
| ENABLE_APP_SANDBOX | NO | 禁用沙盒（f2-cli 需要文件系统访问） |
| ENABLE_HARDENED_RUNTIME | YES | 启用加固运行时 |

### 权限说明

应用需要以下权限：

- **网络访问** - 下载视频需要出站网络连接
- **文件系统读写** - 保存下载的视频文件
- **下载文件夹访问** - 默认保存位置

## 故障排除

### f2-cli 无法执行

```bash
# 添加执行权限
chmod +x dyTool/Resources/f2-cli

# 移除隔离属性（如果从网络下载）
xattr -d com.apple.quarantine dyTool/Resources/f2-cli
```

### 签名问题

如果遇到签名问题，确保：

1. 在 Xcode 中正确配置 Team
2. 证书在钥匙串中有效
3. 使用正确的 Provisioning Profile

### 运行时找不到 f2-cli

检查 f2-cli 是否正确包含在 app bundle 中：

```bash
# 查看打包后的资源
ls -la /path/to/dyTool.app/Contents/Resources/
```

## 开发调试

### 日志查看

运行时日志保存在 `logs/` 目录：

```bash
tail -f logs/f2-*.log
```

### Debug 模式

Debug 模式下，f2-cli 会尝试使用开发路径作为备用：

```swift
#if DEBUG
let devPath = URL(fileURLWithPath: "/Users/everless/project/douyintool/dyTool/dyTool/Resources/f2-cli")
#endif
```
