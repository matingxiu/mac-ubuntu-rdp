# 技术原理：为什么 Mac 版 Windows App 黑屏

## 现象

| 客户端 | 连接 gnome-remote-desktop | 结果 |
|--------|--------------------------|------|
| Windows mstsc.exe | ✅ 正常显示 | 画面清晰 |
| Mac Windows App | ❌ 黑屏 | 能连上，但画面传不过来 |
| FreeRDP + 禁用高级编码 | ✅ 正常显示 | 画面清晰 |

## 根本原因：RDP 编码协商不兼容

RDP 协议在连接建立时会进行**编码能力协商**：客户端声明"我支持哪些编码"，服务器回复"我用哪个"。

### gnome-remote-desktop 的限制

Ubuntu 的 `gnome-remote-desktop`（screen-share / `mirror-primary` 模式）定位是**共享本机屏幕**，不是完整的远程桌面会话，因此只实现了基础编码：

| 编码 | 支持 |
|------|------|
| RDP 6.0 基础位图 | ✅ |
| NSCodec | ✅ |
| RemoteFX (RFX) | ❌ |
| GFX 管道（RDP 8.1+ 图形流水线） | ❌ |
| AVC420 / AVC444 (H.264) | ❌ |

### 三个客户端的回退能力差异

当服务器拒绝高级编码后，**客户端能否优雅回退到基础编码**是关键：

```
客户端发送能力声明 → 服务器拒绝 GFX → 客户端回退 → 结果
```

| 客户端 | 默认尝试 | 回退机制 | 结果 |
|--------|---------|---------|------|
| Windows mstsc.exe | GFX/AVC444 | ✅ 完善 | 正常显示 |
| Mac Windows App | GFX/AVC444 | ❌ 回退不完善 | 黑屏 |
| FreeRDP `-gfx -rfx -nsc -jpeg` | 主动声明只支持基础位图 | 不需要回退 | 正常显示 |

### Mac Windows App 的缺陷

1. **回退机制不完善**：当服务器不支持 GFX 时，协商卡死，画面传不过来（黑屏）
2. **不严格尊重 `.rdp` 文件参数**：即使 `.rdp` 写了 `gfx:i:0`、`avc444:i:0`，Mac 版仍会在协商阶段发送 GFX 能力声明

> 这是微软自己在 Mac 版实现上的缺陷，不是用户配置问题。Windows 版 mstsc.exe 严格遵守 `.rdp` 参数，所以正常。

## 解决方案：FreeRDP 主动禁用高级编码

关键在连接参数 `-gfx -rfx -nsc -jpeg`：

```bash
sdl-freerdp \
    /v:HOST:PORT \
    /u:USER /p:PASSWORD \
    /sec:nla \                    # NLA 认证
    -gfx -rfx -nsc -jpeg \        # ← 关键：禁用所有高级编码
    /bpp:24 \                     # 24 位色
    /size:1920x1080 \
    +dynamic-resolution \         # 动态分辨率
    /cert:tofu \                  # trust-on-first-use
    +clipboard -wallpaper -themes
```

这些参数让 FreeRDP 在**初始协商包里就主动声明"我不支持任何高级编码"**，服务器一看客户端只要基础位图，直接用 NSCodec / 位图流发画面，全程不触发 GFX 协商路径。

## 为什么用 NLA

gnome-remote-desktop 默认只接受 **NLA (Network Level Authentication)**：

```
/sec:tls → 服务器拒绝，要求 HYBRID (NLA)
/sec:rdp → 服务器拒绝，要求 HYBRID (NLA)
/sec:nla → 成功
```

## 为什么用 bash -l 启动

直接用 `Process` 启动 FreeRDP 时，winpr 的 `getaddrinfo` 会因找不到 openssl 等动态库而失败（launchd 环境变量不完整）。

解决：通过 `bash -l`（登录 shell）启动，加载 `~/.zprofile` / `~/.bash_profile` 中的 PATH 和 DYLD 环境变量。

## 安全：TLS 指纹

默认 `/cert:ignore` 跳过证书验证不安全。本项目改用 **trust-on-first-use (TOFU)**：

- `/cert:tofu`：首次连接时记录服务器证书指纹
- 后续连接自动验证指纹，防止中间人攻击
- 指纹存储在 `servers.json` 的 `trusted_fingerprint` 字段

## 参考

- [gnome-remote-desktop](https://gitlab.gnome.org/GNOME/gnome-remote-desktop)
- [FreeRDP](https://github.com/FreeRDP/FreeRDP)
- [MS-RDPBCGR: Remote Desktop Protocol](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-rdpbcgr/)
