# Mac Ubuntu RDP Client

> macOS 原生 RDP 客户端，解决 Mac 版 Windows App 连接 Ubuntu `gnome-remote-desktop` 黑屏问题。

## 背景

Mac 版 Windows App（前身 Microsoft Remote Desktop）连接 Ubuntu gnome-remote-desktop 时出现**黑屏**：能连上但画面传不过来。而 Windows 系统自带的 `mstsc.exe` 却能正常显示。

根本原因是 **RDP 编码协商不兼容**：gnome-remote-desktop 的 screen-share 模式只支持基础位图编码，而 Mac 版 Windows App 强制使用 GFX/AVC444 高级编码，且回退机制有缺陷，又不严格尊重 `.rdp` 文件中的禁用参数。详见 [技术原理](docs/TECHNICAL.md)。

本项目用 **FreeRDP + 原生 Swift GUI** 替代：FreeRDP 在初始协商就主动声明"只用基础编码"，绕过 GFX 协商路径，画面正常显示。

## 功能

- 🖥️ **原生 Cocoa GUI**：Swift 编写，支持 macOS 13+
- 📋 **多服务器管理**：添加 / 编辑 / 删除 / 双击连接
- 🔍 **搜索过滤**：按名称、地址、用户名实时搜索
- 🧪 **测试连接**：一键检查端口可达性
- ↕️ **滑动操作**：表格行右滑编辑 / 删除
- 📤 **导入 / 导出**：JSON 格式配置文件
- 🔒 **TLS 指纹**：trust-on-first-use，首次连接记录证书指纹
- 📝 **日志查看**：一键打开连接日志定位问题
- 🎨 **Ubuntu 图标**：官方 Circle of Friends 配色

## 依赖

只需一个外部依赖：

```bash
brew install freerdp
```

要求 `sdl-freerdp`（FreeRDP 3.x SDL 客户端），默认位于 `/opt/homebrew/bin/sdl-freerdp`。

## 安装

### 方式一：下载 DMG 安装包（推荐）

1. 从 [Releases](../../releases) 下载 `Ubuntu-RDP-x.x.x.dmg`
2. 打开 DMG，把 **Ubuntu RDP** 拖到 **Applications** 文件夹
3. 首次打开右键 → 打开（绕过 Gatekeeper）
4. 确保已安装 FreeRDP（见上方依赖）

### 方式二：自行构建

```bash
git clone https://github.com/USER/mac-ubuntu-rdp.git
cd mac-ubuntu-rdp
./build.sh install
```

## 使用

1. 打开 **Ubuntu RDP**（Spotlight 搜索或 `/Applications`）
2. 点工具栏 **➕** 添加服务器
   - 名称、主机地址、端口、用户名、密码、分辨率、窗口模式
3. **双击**表格行或点 ▶️ 连接
4. SDL 窗口显示 Ubuntu 桌面

### 窗口模式

| 模式 | 说明 |
|------|------|
| smart | 可调整大小窗口（默认，支持最大化，画面动态缩放） |
| fullscreen | 启动即全屏 |
| both | 全屏 + 可调整大小 |
| fixed | 固定大小窗口 |

### 快捷键（SDL 窗口内）

| 快捷键 | 作用 |
|--------|------|
| 右 Shift + 回车 | 切换全屏 |
| 右 Shift + R | 切换窗口可调整大小 |
| 右 Shift + D | 断开连接 |

## 配置文件

`~/.config/ubuntu-rdp/servers.json`

```json
{
  "servers": [
    {
      "id": "UUID",
      "name": "Ubuntu 主机",
      "host": "192.168.1.100",
      "port": 3389,
      "user": "username",
      "password": "your-password",
      "width": 1920,
      "height": 1080,
      "window_mode": "smart",
      "trusted_fingerprint": null
    }
  ],
  "lastSelectedId": "UUID"
}
```

支持从旧版 `~/.config/ubuntu-rdp/config`（KEY=VALUE 格式）自动迁移。

## 构建

```bash
./build.sh           # 构建到 build/
./build.sh install   # 构建并安装到 /Applications
```

要求：macOS 13+，Xcode Command Line Tools（`swiftc`）。

## 项目结构

```
mac-ubuntu-rdp/
├── Sources/
│   ├── main.swift                 # 应用入口 + AppDelegate
│   ├── Logger.swift               # 线程安全文件日志
│   ├── Models.swift               # Server / AppConfig 数据模型
│   ├── ConfigStore.swift          # JSON 读写 + 旧格式迁移 + 导入导出
│   ├── ConnectionManager.swift    # FreeRDP 启动 + 测试连接 + TLS 指纹
│   ├── ServerFormController.swift # 添加/编辑表单窗口（含默认值记忆）
│   ├── MainWindowController.swift # 主窗口 + 工具栏 + 搜索 + 窗口状态持久化
│   ├── SidebarViewController.swift # 侧边栏服务器列表 + 右键菜单 + 空状态
│   └── DetailViewController.swift # 详情面板（居中布局）
├── Resources/
│   ├── Info.plist
│   └── Ubuntu.icns
├── docs/
│   └── TECHNICAL.md              # 技术原理
├── build.sh                       # 构建脚本
├── dmg.sh                         # DMG 打包脚本
├── LICENSE
└── README.md
```

## 技术原理

为什么 Mac 版 Windows App 黑屏？详见 [docs/TECHNICAL.md](docs/TECHNICAL.md)。

## License

MIT
