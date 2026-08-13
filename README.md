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

**DMG 安装包已内置 FreeRDP 及全部依赖（约 50MB），无需额外安装。**

自行构建时需要 FreeRDP（打包脚本会自动将其及依赖复制进 .app）：

```bash
brew install freerdp
```

## 安装

### 方式一：下载 DMG 安装包（推荐）

1. 从 [Releases](../../releases) 下载 `Ubuntu-RDP-x.x.x.dmg`
2. 打开 DMG，把 **Ubuntu RDP** 拖到 **Applications** 文件夹
3. 首次打开右键 → 打开（绕过 Gatekeeper）

> DMG 已内置 FreeRDP，无需额外安装任何依赖。

### 方式二：自行构建

```bash
git clone https://github.com/matingxiu/mac-ubuntu-rdp.git
cd mac-ubuntu-rdp
brew install freerdp dylibbundler cmake pkgconf  # 构建依赖
./build_freerdp_patched.sh   # 编译带剪贴板修复的 FreeRDP（推荐）
./build.sh install
```

> `build_freerdp_patched.sh` 会下载 FreeRDP 3.30.0 源码、应用剪贴板修复 patch 并编译。
> 跳过此步仍可构建，但 Mac→Linux 剪贴板同步不可用（FreeRDP issue #13118）。

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
| fixed | 固定大小窗口 |

> 想要真全屏：连接后手动点 sdl-freerdp 窗口的绿色全屏按钮（效果稳定）。

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
      "trusted_fingerprint": null,
      "auto_fit_screen": true,
      "smart_sizing": true,
      "swap_ctrl_cmd": true
    }
  ],
  "lastSelectedId": "UUID"
}
```

支持从旧版 `~/.config/ubuntu-rdp/config`（KEY=VALUE 格式）自动迁移。

## 安全

- **密码不在脚本中**：凭据通过临时 env 文件（0o600）传递，runner.sh 加载后立即删除
- **密码不在进程列表**：FreeRDP 启动后自动用星号遮蔽 argv 中的密码
- **TLS 指纹**：trust-on-first-use，首次连接记录证书指纹，后续校验防中间人
- **配置文件权限**：runner.sh 0o600，仅 owner 可读写

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
├── bundle_freerdp.sh              # FreeRDP + 依赖打包脚本
├── build_freerdp_patched.sh       # 编译带剪贴板修复的 FreeRDP
├── patches/                       # FreeRDP 源码 patch（剪贴板修复）
├── dmg.sh                         # DMG 打包脚本
├── LICENSE
└── README.md
```

## 技术原理

为什么 Mac 版 Windows App 黑屏？详见 [docs/TECHNICAL.md](docs/TECHNICAL.md)。

## License

MIT
