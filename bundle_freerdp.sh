#!/bin/bash
# bundle_freerdp.sh — 将 FreeRDP 及其依赖打包进 .app bundle
# 用法: ./bundle_freerdp.sh <path-to-app.app>
set -e

APP="${1:?用法: $0 <app.app>}"
MACOS_DIR="$APP/Contents/MacOS"
FRAMEWORKS_DIR="$APP/Contents/Frameworks"
BINARY="sdl-freerdp"

# 查找 brew 安装的 sdl-freerdp
SOURCE=$(which sdl-freerdp 2>/dev/null || echo "/opt/homebrew/bin/sdl-freerdp")
if [ ! -f "$SOURCE" ]; then
    echo "❌ 未找到 sdl-freerdp，请先 brew install freerdp"
    exit 1
fi

echo "📦 源二进制: $SOURCE"
echo "📁 目标: $MACOS_DIR/$BINARY"

# 1. 复制 sdl-freerdp 到 .app/Contents/MacOS/
mkdir -p "$MACOS_DIR"
cp "$SOURCE" "$MACOS_DIR/$BINARY"
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

# 3. 验证
echo ""
echo "✅ 打包完成"
echo "   二进制: $(ls -lh "$MACOS_DIR/$BINARY" | awk '{print $5}')"
echo "   dylib 数: $(find "$FRAMEWORKS_DIR" -name '*.dylib' | wc -l | tr -d ' ')"
echo "   Frameworks 体积: $(du -sh "$FRAMEWORKS_DIR" | awk '{print $1}')"
echo "   .app 总体积: $(du -sh "$APP" | awk '{print $1}')"

# 4. 检查是否还有指向 /opt/homebrew 的残留依赖
echo ""
echo "🔍 检查残留的 homebrew 路径..."
RESIDUAL=$(otool -L "$MACOS_DIR/$BINARY" | grep -c "/opt/homebrew" || true)
if [ "$RESIDUAL" -gt 0 ]; then
    echo "⚠️  二进制仍有 $RESIDUAL 个 homebrew 路径引用:"
    otool -L "$MACOS_DIR/$BINARY" | grep "/opt/homebrew"
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
