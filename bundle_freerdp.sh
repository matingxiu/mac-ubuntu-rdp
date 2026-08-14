#!/bin/bash
# bundle_freerdp.sh — 将 FreeRDP 及其依赖打包进 .app bundle
# 用法: ./bundle_freerdp.sh <path-to-app.app>
set -e

APP="${1:?用法: $0 <app.app>}"
MACOS_DIR="$APP/Contents/MacOS"
FRAMEWORKS_DIR="$APP/Contents/Frameworks"
BINARY="sdl-freerdp"

# 检查 patched 二进制是否存在（修复 macOS 剪贴板 Mac→Linux 同步问题，FreeRDP issue #13118）
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PATCHED_BIN="$SCRIPT_DIR/build/freerdp-patched/sdl-freerdp"

# dylibbundler 无法处理 patched 二进制的 @rpath 引用（会陷入循环依赖），
# 所以始终用 brew 二进制跑 dylibbundler 收集依赖，再替换为 patched 二进制并修复路径
BREW_BIN=$(which sdl-freerdp 2>/dev/null || echo "/opt/homebrew/bin/sdl-freerdp")
if [ ! -f "$BREW_BIN" ]; then
    echo "❌ 未找到 sdl-freerdp，请先 brew install freerdp"
    exit 1
fi

if [ -f "$PATCHED_BIN" ]; then
    echo "📦 使用 patched 二进制（剪贴板修复）+ brew 二进制收集依赖"
else
    echo "⚠️  无 patched 二进制，Mac→Linux 剪贴板同步不可用"
    echo "   要修复剪贴板，请运行: ./build_freerdp_patched.sh"
fi

echo "📁 目标: $MACOS_DIR/$BINARY"

# 1. 复制 brew sdl-freerdp 到 .app/Contents/MacOS/（用于 dylibbundler）
mkdir -p "$MACOS_DIR"
cp "$BREW_BIN" "$MACOS_DIR/$BINARY"
chmod +x "$MACOS_DIR/$BINARY"

# 2. 用 dylibbundler 收集所有依赖到 Frameworks，修复路径为 @executable_path/../Frameworks/
echo "🔗 收集依赖 dylib 并修复路径..."
mkdir -p "$FRAMEWORKS_DIR"
dylibbundler \
    -x "$MACOS_DIR/$BINARY" \
    -b \
    -d "$FRAMEWORKS_DIR" \
    -p "@executable_path/../Frameworks/" \
    -of \
    2>&1 | tail -10

# 2a. 如果有 patched 二进制，替换并修复库路径
if [ -f "$PATCHED_BIN" ]; then
    echo "🔧 替换为 patched 二进制并修复库路径..."
    cp "$PATCHED_BIN" "$MACOS_DIR/$BINARY"
    chmod +x "$MACOS_DIR/$BINARY"

    # 获取 bundled 库的实际文件名（dylibbundler 可能用全版本号命名）
    FW="@executable_path/../Frameworks"
    for dep in libfreerdp-client3 libfreerdp3 libwinpr3; do
        # 查找 Frameworks 中匹配的 dylib
        DYLIB=$(find "$FRAMEWORKS_DIR" -name "${dep}*.dylib" | head -1)
        if [ -n "$DYLIB" ]; then
            DYLIB_NAME=$(basename "$DYLIB")
            # 修复 @rpath/ 引用为 @executable_path/../Frameworks/
            install_name_tool -change "@rpath/${dep}.3.dylib" "$FW/$DYLIB_NAME" "$MACOS_DIR/$BINARY" 2>/dev/null
        fi
    done
    # 修复 SDL 库路径（用 grep -F 固定字符串匹配，避免正则误匹配）
    for dep in "libSDL3_ttf" "libSDL3."; do
        DYLIB=$(find "$FRAMEWORKS_DIR" -name "${dep}*dylib" | head -1)
        if [ -n "$DYLIB" ]; then
            DYLIB_NAME=$(basename "$DYLIB")
            # 修复绝对路径引用（grep -F 避免正则匹配多条记录）
            OLD_REF=$(otool -L "$MACOS_DIR/$BINARY" | grep -F "${dep}" | awk '{print $1}' | head -1)
            if [ -n "$OLD_REF" ]; then
                install_name_tool -change "$OLD_REF" "$FW/$DYLIB_NAME" "$MACOS_DIR/$BINARY" 2>/dev/null
            fi
        fi
    done
    # 删除所有 rpath 条目，添加 bundle rpath
    for rpath in $(otool -l "$MACOS_DIR/$BINARY" | grep -A2 LC_RPATH | grep "path " | awk '{print $2}'); do
        install_name_tool -delete_rpath "$rpath" "$MACOS_DIR/$BINARY" 2>/dev/null
    done
    install_name_tool -add_rpath "$FW/" "$MACOS_DIR/$BINARY" 2>/dev/null
    echo "  ✓ patched 二进制已就位"
fi

# 2b. 复制 OpenSSL 运行时模块（dlopen 加载，dylibbundler 管不到）
echo "🔐 复制 OpenSSL 模块..."
OSSL_SRC="$(brew --prefix openssl@3)/lib/ossl-modules"
if [ -d "$OSSL_SRC" ]; then
    mkdir -p "$FRAMEWORKS_DIR/ossl-modules"
    cp "$OSSL_SRC"/*.dylib "$FRAMEWORKS_DIR/ossl-modules/" 2>/dev/null
    # 修复模块内对 libcrypto 的引用
    for mod in "$FRAMEWORKS_DIR/ossl-modules"/*.dylib; do
        [ -f "$mod" ] || continue
        # 获取当前 libcrypto 引用路径
        CRYPTO_REF=$(otool -L "$mod" | grep "libcrypto" | awk '{print $1}' | head -1)
        if [ -n "$CRYPTO_REF" ]; then
            install_name_tool -change "$CRYPTO_REF" "@executable_path/../Frameworks/libcrypto.3.dylib" "$mod" 2>/dev/null
        fi
        # ad-hoc 重签名
        codesign --force --sign - "$mod" 2>/dev/null
    done
    echo "  ✓ ossl-modules: $(ls "$FRAMEWORKS_DIR/ossl-modules/" | wc -l | tr -d ' ') 个模块"
else
    echo "  ⚠️ 未找到 OpenSSL 模块目录"
fi

# 3. 创建 FreeRDP.app 包装器（LSUIElement=true，不在 Dock 显示独立图标）
echo "🍎 创建 FreeRDP.app 包装器（LSUIElement）..."
WRAPPER_APP="$APP/Contents/Resources/FreeRDP.app"
WRAPPER_MACOS="$WRAPPER_APP/Contents/MacOS"
mkdir -p "$WRAPPER_MACOS"

# 移动 sdl-freerdp 到包装器中（实际复制，非符号链接，确保 @executable_path 正确）
mv "$MACOS_DIR/$BINARY" "$WRAPPER_MACOS/$BINARY"

# 创建 Info.plist（LSUIElement=true 使 NSApplication 使用 accessory 策略，无 Dock 图标）
cat > "$WRAPPER_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>sdl-freerdp</string>
    <key>CFBundleIdentifier</key>
    <string>com.ubuntu-rdp.freerdp</string>
    <key>CFBundleName</key>
    <string>FreeRDP</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

# 创建 Frameworks 符号链接（指向主 .app 的 Frameworks）
# 路径: FreeRDP.app/Contents/Frameworks -> ../../../Frameworks
# 解析: FreeRDP.app/Contents/ -> FreeRDP.app/ -> Resources/ -> Contents/ -> Frameworks/
ln -sf ../../../Frameworks "$WRAPPER_APP/Contents/Frameworks"

# ad-hoc 签名包装器 .app
codesign --force --deep --sign - "$WRAPPER_APP" 2>/dev/null

echo "  ✓ FreeRDP.app 包装器创建完成（LSUIElement=true）"

# 4. 验证
WRAPPER_BINARY="$WRAPPER_MACOS/$BINARY"
echo ""
echo "✅ 打包完成"
echo "   二进制: $(ls -lh "$WRAPPER_BINARY" | awk '{print $5}')"
echo "   dylib 数: $(find "$FRAMEWORKS_DIR" -name '*.dylib' | wc -l | tr -d ' ')"
echo "   Frameworks 体积: $(du -sh "$FRAMEWORKS_DIR" | awk '{print $1}')"
echo "   .app 总体积: $(du -sh "$APP" | awk '{print $1}')"

# 5. 检查是否还有指向 /opt/homebrew 的残留依赖
echo ""
echo "🔍 检查残留的 homebrew 路径..."
RESIDUAL=$(otool -L "$WRAPPER_BINARY" | grep -c "/opt/homebrew" || true)
if [ "$RESIDUAL" -gt 0 ]; then
    echo "⚠️  二进制仍有 $RESIDUAL 个 homebrew 路径引用:"
    otool -L "$WRAPPER_BINARY" | grep "/opt/homebrew"
else
    echo "✓ 无 homebrew 路径残留"
fi

# 检查所有 dylib
DYLIB_RESIDUAL=$(find "$FRAMEWORKS_DIR" -name '*.dylib' -exec otool -L {} \; 2>/dev/null | grep -c "/opt/homebrew" || true)
if [ "$DYLIB_RESIDUAL" -gt 0 ]; then
    echo "⚠️  dylib 中仍有 $DYLIB_RESIDUAL 个 homebrew 路径引用（可能需要手动修复）"
else
    echo "✓ dylib 无 homebrew 路径残留"
fi

# 6. 验证 Frameworks 符号链接
echo ""
echo "🔗 验证 Frameworks 符号链接..."
if [ -d "$WRAPPER_APP/Contents/Frameworks" ]; then
    echo "✓ 符号链接有效: $(readlink "$WRAPPER_APP/Contents/Frameworks")"
    echo "  实际解析到: $(cd "$WRAPPER_APP/Contents/Frameworks" && pwd)"
else
    echo "✗ 符号链接无效!"
fi
