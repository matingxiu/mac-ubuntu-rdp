# Ubuntu RDP 设计文档

> 版本：2.0.0 | 最后更新：2026-07-30

## 1. 项目概述

### 1.1 项目背景

Mac 版 Windows App（前身 Microsoft Remote Desktop）连接 Ubuntu `gnome-remote-desktop` 时存在**黑屏问题**：连接能建立但画面传不过来。而 Windows 系统自带的 `mstsc.exe` 却能正常显示。

根本原因是 **RDP 编码协商不兼容**：gnome-remote-desktop 的 screen-share 模式只支持基础位图编码，而 Mac 版 Windows App 强制使用 GFX/AVC444 高级编码，且回退机制有缺陷，又不严格尊重 `.rdp` 文件中的禁用参数。

### 1.2 解决方案

使用 **FreeRDP + 原生 Swift GUI** 替代 Mac 版 Windows App。FreeRDP 在初始协商阶段就主动声明"只用基础编码"，绕过 GFX 协商路径，画面正常显示。

### 1.3 目标用户

需要在 macOS 上通过 RDP 协议远程连接 Ubuntu 桌面（gnome-remote-desktop）的开发者和运维人员。

### 1.4 核心价值

- **解决黑屏痛点**：绕过 Mac 版 Windows App 的编码协商缺陷
- **原生体验**：纯 Swift/Cocoa 实现，无 Electron/WebView 依赖
- **零门槛**：仅依赖 FreeRDP（`brew install freerdp`），一键安装
- **轻量管理**：多服务器配置管理，支持导入导出

---

## 2. 系统架构

### 2.1 架构总览

```
┌─────────────────────────────────────────────────────────────┐
│                     Ubuntu RDP App                          │
│                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │  AppDelegate │  │ MainWindow   │  │  ServerForm  │     │
│  │  (入口/菜单) │──│ Controller   │──│  Controller  │     │
│  └──────────────┘  └──────┬───────┘  └──────────────┘     │
│                           │                                 │
│              ┌────────────┼────────────┐                    │
│              ▼            ▼            ▼                    │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐       │
│  │  Sidebar     │ │  Detail      │ │  Statusbar   │       │
│  │  ViewController│ │ ViewController│ │  Container  │       │
│  └──────────────┘ └──────────────┘ └──────────────┘       │
│                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │  ConfigStore │  │  Connection  │  │  Logger      │     │
│  │  (持久化)    │  │  Manager     │  │  (日志)      │     │
│  └──────────────┘  └──────────────┘  └──────────────┘     │
│                                                             │
│  ┌──────────────┐                                          │
│  │  Models      │  Server / AppConfig 数据模型             │
│  └──────────────┘                                          │
└─────────────────────────────────────────────────────────────┘
          │                    │
          ▼                    ▼
  ┌──────────────┐    ┌──────────────┐
  │ servers.json │    │  FreeRDP     │
  │ (配置文件)    │    │  (外部进程)   │
  └──────────────┘    └──────────────┘
```

### 2.2 分层设计

| 层级 | 组件 | 职责 |
|------|------|------|
| **应用层** | AppDelegate | 应用生命周期、菜单栏、FreeRDP 依赖检测 |
| **窗口层** | MainWindowController | 主窗口管理、工具栏、搜索、窗口状态持久化 |
| **视图层** | SidebarViewController / DetailViewController / ServerFormController | 服务器列表、详情面板、表单编辑 |
| **业务层** | ConnectionManager | FreeRDP 启动、连接测试、TLS 指纹管理 |
| **持久层** | ConfigStore | JSON 读写、旧格式迁移、导入导出 |
| **基础层** | Logger / Models | 线程安全日志、数据模型 |

### 2.3 设计原则

- **单例管理**：`ConfigStore`、`ConnectionManager`、`Logger` 均为单例，确保状态一致性
- **回调驱动**：视图间通过闭包回调（`onSelect`、`onConnect`、`onEdit` 等）通信，避免直接耦合
- **原子写入**：配置文件使用 `atomic` 选项写入，避免写入中断导致数据损坏
- **进程隔离**：FreeRDP 作为独立进程运行，通过 shell 脚本桥接，避免库依赖冲突

---

## 3. 数据模型

### 3.1 Server 模型

```
┌─────────────────────────────────────────────────────┐
│  Server                                             │
├─────────────────────────────────────────────────────┤
│  id: UUID                  # 唯一标识符             │
│  name: String              # 服务器名称             │
│  host: String              # 主机地址               │
│  port: Int                 # 端口号 (默认 3389)     │
│  user: String              # 用户名                 │
│  password: String          # 密码                   │
│  width: Int                # 分辨率宽度 (默认 1920) │
│  height: Int               # 分辨率高度 (默认 1080) │
│  windowMode: String        # 窗口模式               │
│  trustedFingerprint: String? # TLS 证书指纹 (TOFU)  │
│  autoFitScreen: Bool       # 自动适配 Mac 屏幕      │
│  smartSizing: Bool         # 智能缩放               │
├─────────────────────────────────────────────────────┤
│  计算属性:                                           │
│  address → "host:port"                              │
│  resolution → "widthxheight"                        │
│  isValid → 名称/地址/用户名非空且端口合法            │
│  isComplete → isValid 且密码非空                     │
│  windowModeDescription → 中文描述                    │
│  shellSafeHost → 安全 shell 主机名                   │
└─────────────────────────────────────────────────────┘
```

**JSON 序列化键名映射**（snake_case）：

| 属性 | JSON 键 |
|------|---------|
| windowMode | window_mode |
| trustedFingerprint | trusted_fingerprint |
| autoFitScreen | auto_fit_screen |
| smartSizing | smart_sizing |

**向后兼容**：自定义 `init(from decoder:)`，对 `id`、`autoFitScreen`、`smartSizing` 使用 `decodeIfPresent`，缺失时提供默认值。

### 3.2 AppConfig 模型

```
┌─────────────────────────────────┐
│  AppConfig                      │
├─────────────────────────────────┤
│  servers: [Server]              │
│  lastSelectedId: UUID?          │
├─────────────────────────────────┤
│  static empty → 空配置          │
└─────────────────────────────────┘
```

### 3.3 窗口模式

| 模式 | 值 | FreeRDP 参数 | 说明 |
|------|-----|-------------|------|
| smart | `smart` | `+dynamic-resolution` | 可调整大小窗口（默认） |
| fullscreen | `fullscreen` | `/f +dynamic-resolution` | 启动即全屏 |
| both | `both` | `/f +dynamic-resolution` | 全屏 + 可调整大小 |
| fixed | `fixed` | （无） | 固定大小窗口 |

---

## 4. 模块详细设计

### 4.1 应用入口 — main.swift

**职责**：应用启动、菜单栏构建、FreeRDP 依赖检测

**流程**：

```
启动 → 创建 NSApplication → 设置 AppDelegate
     → applicationDidFinishLaunching:
        ├─ setupMenu() → 构建菜单栏（App/文件/服务器/编辑）
        ├─ 检查 FreeRDP 是否安装 → 未安装则弹窗警告
        └─ 创建 MainWindowController → showWindow → 激活应用
```

**菜单结构**：

| 菜单 | 项目 | 快捷键 |
|------|------|--------|
| App 菜单 | 关于/隐藏/隐藏其他/显示全部/退出 | ⌘Q 等 |
| 文件 | 新建服务器 | ⌘N |
| | 导入配置 | ⌘I |
| | 导出配置 | ⇧⌘E |
| | 关闭窗口 | ⌘W |
| 服务器 | 连接 | ↵ |
| | 测试连接 | ⌘T |
| | 编辑服务器 | ⌘E |
| | 删除 | ⌫ |
| 编辑 | 剪切/复制/粘贴/全选 | ⌘X/C/V/A |

### 4.2 主窗口 — MainWindowController

**职责**：主窗口管理、双栏布局、工具栏、搜索、窗口状态持久化

**窗口属性**：

- 默认尺寸：780×480
- 最小尺寸：600×360
- 样式：titled + closable + miniaturizable + resizable + fullSizeContentView + unifiedTitleAndToolbar
- 透明标题栏（`titlebarAppearsTransparent = true`）

**双栏布局**：

```
┌──────────────────────────────────────────────┐
│  [导入] [导出] [搜索框]              [日志]   │  ← 工具栏
├──────────────┬───────────────────────────────┤
│  服务器列表    │  服务器详情                    │
│  (Sidebar)   │  (Detail)                     │
│              │                               │
│  🖥 主机1     │  🖥 服务器名称                 │
│  🖥 主机2     │  192.168.1.100:3389           │
│  🖥 主机3     │                               │
│              │  用户名: mtx                   │
│              │  端口: 3389                    │
│              │  分辨率: 自动适配屏幕           │
│              │  窗口模式: smart (可调整大小)   │
│              │  智能缩放: 开启                │
│              │                               │
│              │  [▶连接] [测试连接] [编辑]      │
│              │                               │
├──────────────┴───────────────────────────────┤
│  共 3 个服务器                        ⏳      │  ← 状态栏
└──────────────────────────────────────────────┘
```

**SplitView 配置**：

| 侧边栏 | 详情面板 |
|---------|---------|
| 最小宽度 220 | 最小宽度 360 |
| 最大宽度 320 | — |
| 不可折叠 | — |

**工具栏项**：

| 标识符 | 图标 | 动作 |
|--------|------|------|
| import | `square.and.arrow.down` | 导入配置 |
| export | `square.and.arrow.up` | 导出配置 |
| search | NSSearchToolbarItem | 搜索过滤 |
| logs | `doc.text.magnifyingglass` | 打开日志文件夹 |

**窗口状态持久化**：

- 使用 `UserDefaults` 保存 `mainWindowFrame`（`NSRect` 字符串）
- 窗口首次成为 key window 后恢复保存的 frame
- 使用重试机制（最多 10 次）应对 NSSplitViewController 初始 layout 覆盖 frame 的问题
- 恢复期间触发的 resize/move 不保存

**搜索过滤**：按名称、地址、用户名实时搜索，搜索字段变更时过滤 `servers` 数组

**回调链路**：

```
SidebarVC.onSelect → 更新 currentSelectionId → 更新 DetailVC.server → 记住选中
SidebarVC.onAdd → addServer() → ServerFormController
SidebarVC.onEdit → editServer() → ServerFormController
SidebarVC.onDelete → deleteServer() → 确认弹窗 → ConfigStore.delete
SidebarVC.onConnect → connect() → ConnectionManager.connect
SidebarVC.onTest → testConnection() → ConnectionManager.testConnection
DetailVC.onConnect / onTest / onEdit → 同上
```

### 4.3 侧边栏 — SidebarViewController

**职责**：服务器列表展示、右键菜单、行滑动操作、空状态提示

**UI 组件**：

- `NSTableView`（inset 样式，无交替行背景，透明背景）
- `NSButton`（底部添加按钮，`+` 图标 + 文字）
- `NSTextField`（空状态标签："没有服务器\n点击下方添加"）

**行视图**：

```
┌────────────────────────────┐
│  🖥  服务器名称              │  ← 22×22 图标 + 13pt medium 文字
└────────────────────────────┘
```

**交互**：

- 单击选中 → `onSelect` 回调
- 双击连接 → `onConnect` 回调
- 右键菜单：连接 / 测试连接 / 编辑 / 删除
- 右滑操作：编辑（蓝色）/ 删除（红色）

**空状态**：当 `servers` 为空时显示提示文字，隐藏表格

### 4.4 详情面板 — DetailViewController

**职责**：选中服务器的预览和操作

**布局**：垂直居中容器

```
     🖥  (64pt 大图标)
  服务器名称  (22pt semibold)
  host:port   (13pt secondary)
  
  用户名:  xxx     (信息表格)
  端口:    3389
  分辨率:  自动适配屏幕
  窗口模式: smart (可调整大小)
  智能缩放: 开启
  
  [▶连接] [测试连接] [编辑]  (按钮区)
```

**空状态**：未选中服务器时显示"从左侧选择一个服务器"

**按钮**：

| 按钮 | 图标 | 尺寸 | 快捷键 |
|------|------|------|--------|
| 连接 | `play.fill` | large | ↵ |
| 测试连接 | `antenna.radiowaves.left.and.right` | regular | — |
| 编辑 | `square.and.pencil` | regular | — |

### 4.5 表单窗口 — ServerFormController

**职责**：添加/编辑服务器配置

**窗口属性**：460×460，仅 titled + closable，模态窗口

**表单字段**：

| 字段 | 键名 | 类型 | Placeholder | 默认值 |
|------|------|------|-------------|--------|
| 名称 | name | NSTextField | "我的 Ubuntu 服务器" | — |
| 主机地址 | host | NSTextField | "192.168.1.100" | — |
| 端口 | port | NSTextField + IntegerFormatter | "3389" | 3389 |
| 用户名 | user | NSTextField | "username" | — |
| 密码 | password | NSSecureTextField | — | — |
| 分辨率宽 | width | NSTextField + IntegerFormatter | "1920" | 1920 |
| 分辨率高 | height | NSTextField + IntegerFormatter | "1080" | 1080 |
| 窗口模式 | windowMode | NSPopUpButton | — | smart |
| 自动适配屏幕 | autoFitScreen | NSButton(checkbox) | — | ✅ |
| 智能缩放 | smartSizing | NSButton(checkbox) | — | ✅ |

**默认值记忆**：新建服务器时，端口/分辨率/窗口模式从 `UserDefaults` 读取上次保存的值

**校验**：名称、主机地址、用户名不能为空

**保存按钮**：橙色背景（`sRGB(0.91, 0.33, 0.13, 1)`），快捷键 ↵

**取消按钮**：快捷键 Esc

### 4.6 配置存储 — ConfigStore

**职责**：JSON 读写、旧格式迁移、导入导出

**文件路径**：

```
~/.config/ubuntu-rdp/
├── servers.json          # 当前配置（JSON）
└── config                # 旧版配置（KEY=VALUE，已废弃）
```

**核心方法**：

| 方法 | 说明 |
|------|------|
| `load()` → `AppConfig` | 加载配置，自动检测并迁移旧格式 |
| `write(_ config:)` | 原子写入 JSON（prettyPrinted + withoutEscapingSlashes） |
| `update(server:)` → `AppConfig` | 原子更新单个服务器（存在则更新，不存在则追加） |
| `delete(id:)` → `AppConfig` | 删除服务器，同时清理 lastSelectedId |
| `export(to url:)` | 导出配置到指定文件 |
| `importConfig(from url:)` → `AppConfig` | 从指定文件导入并覆盖当前配置 |

**旧格式迁移**：

```
检测到 ~/.config/ubuntu-rdp/config（KEY=VALUE 格式）
→ 解析 SERVER=host:port, USER=, PASS=, WIDTH=, HEIGHT=, WINDOW_MODE=
→ 创建 Server 对象
→ 写入 servers.json
→ 迁移完成
```

### 4.7 连接管理 — ConnectionManager

**职责**：FreeRDP 启动、连接测试、TLS 指纹管理

**FreeRDP 检测路径**（按优先级）：

| 优先级 | 路径 | 适用架构 |
|--------|------|---------|
| 1 | `/opt/homebrew/bin/sdl-freerdp` | Apple Silicon |
| 2 | `/usr/local/bin/sdl-freerdp` | Intel |
| 3 | `/opt/homebrew/bin/xfreerdp` | Apple Silicon (备选) |
| 4 | `/usr/local/bin/xfreerdp` | Intel (备选) |

**连接流程**：

```
connect(to: server)
  ├─ 校验 server.isValid
  ├─ 校验 freerdpInstalled
  ├─ buildRunnerScript(for: server) → 生成 runner.sh
  ├─ 写入 ~/Library/Logs/ubuntu-rdp/runner.sh
  ├─ chmod 755
  ├─ Process(launchPath: "/bin/bash", arguments: ["-l", runnerPath])
  ├─ 重定向 stdout/stderr → freerdp.log
  └─ process.run()
```

**FreeRDP 命令参数**：

```bash
exec sdl-freerdp \
    /v:HOST:PORT \              # 连接地址
    /u:"USER" \                 # 用户名
    /p:"PASSWORD" \             # 密码
    /sec:nla \                  # NLA 认证
    -gfx -rfx -nsc -jpeg \     # 禁用高级编码（关键！）
    /bpp:24 \                   # 24 位色深
    /size:WxH \                 # 分辨率
    +dynamic-resolution \       # 动态分辨率（smart 模式）
    /cert:tofu[:fingerprint:FP] \ # TLS 信任首次使用
    /t:"NAME" \                 # 窗口标题
    +clipboard \                # 剪贴板共享
    -wallpaper -themes          # 禁用壁纸/主题（减少带宽）
```

**测试连接**：通过 `nc -z -w 3 HOST PORT` 检测端口可达性（3 秒超时），在后台线程执行

**TLS 指纹管理**：

- 首次连接：使用 `/cert:tofu`，FreeRDP 自动记录指纹
- 后续连接：使用 `/cert:tofu:fingerprint:FP`，自动验证指纹一致性
- 指纹存储在 `servers.json` 的 `trusted_fingerprint` 字段

**为什么用 `bash -l`**：直接用 `Process` 启动 FreeRDP 时，winpr 的 `getaddrinfo` 会因找不到 openssl 等动态库而失败。通过 `bash -l`（登录 shell）启动，加载 `~/.zprofile` / `~/.bash_profile` 中的 PATH 和 DYLD 环境变量。

### 4.8 日志系统 — Logger

**职责**：线程安全的文件日志

**日志路径**：`~/Library/Logs/ubuntu-rdp/`

| 文件 | 说明 |
|------|------|
| app.log | 应用日志 |
| freerdp.log | FreeRDP 运行日志 |
| runner.sh | 自动生成的启动脚本 |

**日志格式**：

```
[ISO8601时间戳] [级别] [文件名:行号] 消息内容
```

**日志级别**：DEBUG / INFO / WARN / ERROR

**线程安全**：使用 `DispatchQueue(label: "com.mtx.ubuntu-rdp.logger")` 的 `sync` 操作确保写入安全

**Debug 模式**：`#if DEBUG` 时同时输出到控制台

### 4.9 状态栏容器 — StatusbarContainerController

**职责**：在主窗口底部嵌入状态栏

**布局**：

```
┌───────────────────────────────────┐
│                                   │
│     SplitView (内容区域)           │
│                                   │
├───────────────────────────────────┤
│  共 3 个服务器           ⏳ 24px  │  ← 状态栏
└───────────────────────────────────┘
```

- 状态文字：11pt，secondaryLabelColor
- 进度指示器：spinning，small，默认隐藏
- 状态栏高度：24pt
- 分隔线背景：separatorColor 15% 透明度

---

## 5. 数据流

### 5.1 配置读写流

```
用户操作 → ServerFormController.save()
         → MainWindowController.addServer() / editServer()
         → ConfigStore.update(server:)
         → ConfigStore.load() + write()
         → MainWindowController.reload()
         → SidebarVC.servers = [...] → tableView.reloadData()
         → DetailVC.server = server → update()
```

### 5.2 连接流

```
用户双击/点击连接 → SidebarVC.onConnect / DetailVC.onConnect
                 → MainWindowController.connect(to:)
                 → ConnectionManager.connect(to:)
                 ├─ 校验 server.isValid
                 ├─ 校验 freerdpInstalled
                 ├─ buildRunnerScript() → runner.sh
                 ├─ Process("/bin/bash", ["-l", runner.sh])
                 └─ 重定向输出 → freerdp.log
```

### 5.3 搜索流

```
用户输入搜索词 → MainWindowController.controlTextDidChange()
              → 过滤 servers 数组（按 name/address/user）
              → SidebarVC.servers = filtered
              → updateStatus()
```

---

## 6. 文件与目录结构

### 6.1 项目源码

```
mac-ubuntu-rdp/
├── Sources/
│   ├── main.swift                 # 应用入口 + AppDelegate
│   ├── Logger.swift               # 线程安全文件日志
│   ├── Models.swift               # Server / AppConfig 数据模型
│   ├── ConfigStore.swift          # JSON 读写 + 旧格式迁移 + 导入导出
│   ├── ConnectionManager.swift    # FreeRDP 启动 + 测试连接 + TLS 指纹
│   ├── ServerFormController.swift # 添加/编辑表单窗口
│   ├── MainWindowController.swift # 主窗口 + 工具栏 + 搜索 + 窗口状态持久化
│   ├── SidebarViewController.swift # 侧边栏服务器列表 + 右键菜单 + 空状态
│   └── DetailViewController.swift # 详情面板（居中布局）
├── Resources/
│   ├── Info.plist
│   └── Ubuntu.icns
├── docs/
│   ├── TECHNICAL.md               # 技术原理
│   └── DESIGN.md                  # 本文档
├── build.sh                       # 构建脚本
├── dmg.sh                         # DMG 打包脚本
├── LICENSE
└── README.md
```

### 6.2 运行时文件

```
~/.config/ubuntu-rdp/
├── servers.json          # 服务器配置（JSON）
└── config                # 旧版配置（KEY=VALUE，已废弃）

~/Library/Logs/ubuntu-rdp/
├── app.log               # 应用日志
├── freerdp.log           # FreeRDP 运行日志
└── runner.sh             # 自动生成的启动脚本

~/Library/Preferences/
└── (UserDefaults)        # 窗口 frame、表单默认值
```

### 6.3 App Bundle 结构

```
Ubuntu RDP.app/
└── Contents/
    ├── Info.plist
    ├── MacOS/
    │   └── Ubuntu-RDP          # Mach-O 64-bit arm64
    └── Resources/
        └── Ubuntu.icns
```

---

## 7. 构建与分发

### 7.1 构建脚本 (build.sh)

```bash
swiftc Sources/*.swift -framework Cocoa -O -o build/Ubuntu-RDP
# 打包 .app bundle
# 可选：./build.sh install → 安装到 /Applications
```

### 7.2 DMG 打包 (dmg.sh)

```
构建 .app → 准备暂存目录 → 创建读写 DMG → 挂载美化布局 → 卸载转只读压缩
```

- 版本号：优先 git tag，否则 `1.0.0`
- DMG 布局：App 左、Applications 右，图标视图 96pt
- 压缩：UDZO，zlib-level=9

### 7.3 系统要求

| 项目 | 要求 |
|------|------|
| macOS | 13.0+ |
| 架构 | Apple Silicon (arm64) |
| FreeRDP | `brew install freerdp`（sdl-freerdp 3.x） |
| Xcode | Command Line Tools（swiftc） |

---

## 8. 错误处理

### 8.1 ConfigError

| 错误 | 说明 |
|------|------|
| `parseError(String)` | JSON 解析失败 |
| `writeError(String)` | 文件写入失败 |
| `readError(String)` | 文件读取失败 |

### 8.2 ConnectionError

| 错误 | 说明 |
|------|------|
| `invalidConfig` | 服务器配置无效（名称/地址/用户名/端口） |
| `scriptWriteFailed(String)` | 运行脚本写入失败 |
| `launchFailed(String)` | FreeRDP 启动失败 |
| `unreachable` | 端口不可达 |
| `testFailed(String)` | 测试连接失败 |

### 8.3 用户级错误提示

| 场景 | 提示方式 |
|------|---------|
| FreeRDP 未安装 | 启动时弹窗警告 |
| 连接失败 | Sheet 弹窗 |
| 配置加载失败 | Sheet 弹窗 |
| 表单验证失败 | Sheet 弹窗 |
| 删除确认 | Sheet 确认框 |

---

## 9. 安全设计

### 9.1 TLS 证书验证

- **Trust-on-First-Use (TOFU)**：首次连接时记录服务器证书指纹，后续连接自动验证
- 指纹存储在 `servers.json` 的 `trusted_fingerprint` 字段
- 不使用不安全的 `/cert:ignore`

### 9.2 密码存储

- 密码以明文存储在 `servers.json` 中
- `servers.json` 位于用户主目录 `~/.config/ubuntu-rdp/`
- 表单中使用 `NSSecureTextField` 输入密码

### 9.3 Shell 注入防护

- `Server.shellSafeHost` 属性过滤主机名，仅允许字母数字、点、横线
- 连接参数通过脚本文件传递，避免直接拼接命令行

---

## 10. 未来规划

### 10.1 短期优化

- [ ] 密码存储加密（Keychain 集成）
- [ ] 服务器分组管理
- [ ] 连接历史记录
- [ ] 自定义 FreeRDP 参数

### 10.2 中期目标

- [ ] SSH 隧道支持
- [ ] 网关代理支持
- [ ] 多显示器支持
- [ ] 拖拽排序

### 10.3 长期愿景

- [ ] SwiftUI 重写
- [ ] iOS/iPadOS 版本
- [ ] 内置 RDP 渲染引擎（替代 FreeRDP 依赖）
