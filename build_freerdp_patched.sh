#!/bin/bash
# build_freerdp_patched.sh — 从源码编译带剪贴板修复的 sdl-freerdp
#
# 修复内容：SDL3 macOS 剪贴板 Has/Get 不匹配问题（FreeRDP issue #13118）
#   SDL_HasClipboardData("text/plain") 返回 true（UTI 一致性匹配）
#   SDL_GetClipboardData("text/plain") 返回 NULL（精确匹配）
#   导致 Mac→Linux 剪贴板同步失败
#
# 修复方式：用 SDL_GetClipboardData 实际读取验证代替 SDL_HasClipboardData 探测
#
# 用法: ./build_freerdp_patched.sh
# 前置: brew install freerdp cmake pkgconf
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PATCH_DIR="$SCRIPT_DIR/patches"
CACHE_DIR="$SCRIPT_DIR/build/freerdp-patched"
SRC_DIR="/tmp/FreeRDP-3.30.0"
TARBALL="/tmp/freerdp-3.30.0.tar.gz"
FREERDP_VERSION="3.30.0"
PATCH_FILE="$PATCH_DIR/freerdp-${FREERDP_VERSION}-clipboard-mac-fix.patch"

echo "=== 构建 patched sdl-freerdp (剪贴板修复) ==="
echo ""

# 1. 检查依赖
echo "① 检查依赖..."
for cmd in cmake sdl-freerdp; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "❌ 未找到 $cmd，请运行: brew install $cmd"
        exit 1
    fi
done
echo "   ✓ 依赖齐全"

# 2. 下载源码（如果已存在则跳过）
echo ""
echo "② 下载 FreeRDP ${FREERDP_VERSION} 源码..."
if [ -d "$SRC_DIR" ] && [ -f "$SRC_DIR/client/SDL/SDL3/sdl_clip.cpp" ]; then
    echo "   ✓ 源码已存在: $SRC_DIR"
else
    if [ ! -f "$TARBALL" ]; then
        echo "   下载 tarball..."
        curl -sL "https://github.com/FreeRDP/FreeRDP/archive/refs/tags/${FREERDP_VERSION}.tar.gz" -o "$TARBALL"
    fi
    echo "   解压..."
    rm -rf "$SRC_DIR"
    tar xzf "$TARBALL" -C /tmp
    echo "   ✓ 源码已解压: $SRC_DIR"
fi

# 3. 应用 patch
echo ""
echo "③ 应用剪贴板修复 patch..."
if [ ! -f "$PATCH_FILE" ]; then
    echo "❌ Patch 文件不存在: $PATCH_FILE"
    exit 1
fi

# 检查是否已经 patch 过（通过检查 sdlHasClipboardData 是否存在）
if grep -q "sdlHasClipboardData" "$SRC_DIR/client/SDL/SDL3/sdl_clip.cpp" 2>/dev/null; then
    echo "   ✓ 已应用过 patch"
else
    cd "$SRC_DIR"
    git init 2>/dev/null || true
    git add -A 2>/dev/null || true
    git commit -m "original" --allow-empty 2>/dev/null || true
    patch -p1 < "$PATCH_FILE"
    echo "   ✓ Patch 已应用"
fi

# 4. 编译
echo ""
echo "④ 编译 sdl-freerdp (可能需要几分钟)..."
mkdir -p "$SRC_DIR/build"

cmake -S "$SRC_DIR" -B "$SRC_DIR/build" \
    -DBUILD_SHARED_LIBS=ON \
    -DWITH_X11=ON \
    -DWITH_JPEG=ON \
    -DWITH_MANPAGES=OFF \
    -DWITH_WEBVIEW=OFF \
    -DWITH_CLIENT_SDL=ON \
    -DWITH_CLIENT_SDL2=OFF \
    -DWITH_CLIENT_SDL3=ON \
    -DCHANNEL_RDPEWA=ON \
    -DWITH_CLIENT_MAC=OFF \
    -DWITH_PLATFORM_SERVER=OFF \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES="arm64" \
    2>&1 | tail -5

cmake --build "$SRC_DIR/build" --target sdl3-freerdp -j"$(sysctl -n hw.ncpu)" 2>&1 | tail -5

BUILT_BIN="$SRC_DIR/build/client/SDL/SDL3/sdl-freerdp"
if [ ! -f "$BUILT_BIN" ]; then
    echo "❌ 编译失败：未找到 $BUILT_BIN"
    exit 1
fi
echo "   ✓ 编译成功"

# 5. 缓存 patched 二进制（清理 build 目录 rpath，避免 dylibbundler 循环依赖）
echo ""
echo "⑤ 缓存 patched 二进制..."
mkdir -p "$CACHE_DIR"
cp "$BUILT_BIN" "$CACHE_DIR/sdl-freerdp"

# 删除指向 /tmp build 目录的 rpath 条目，只保留 /opt/homebrew/lib
# （dylibbundler 遇到 build 目录的 rpath 会陷入循环依赖）
for rpath in $(otool -l "$CACHE_DIR/sdl-freerdp" | grep -A2 LC_RPATH | grep "path /tmp" | awk '{print $2}'); do
    install_name_tool -delete_rpath "$rpath" "$CACHE_DIR/sdl-freerdp" 2>/dev/null
done
codesign --force --sign - "$CACHE_DIR/sdl-freerdp"
echo "   ✓ 已缓存到: $CACHE_DIR/sdl-freerdp（rpath 已清理）"

# 验证 patch
if nm "$CACHE_DIR/sdl-freerdp" 2>/dev/null | grep -q sdlHasClipboardData; then
    echo "   ✓ Patch 验证通过（sdlHasClipboardData 符号存在）"
else
    echo "   ⚠️ Patch 验证：未找到 sdlHasClipboardData 符号（可能是内联优化）"
fi

echo ""
echo "=== 完成 ✓ ==="
echo "patched 二进制: $CACHE_DIR/sdl-freerdp"
echo ""
echo "下次运行 ./build.sh 或 ./bundle_freerdp.sh 时将自动使用此 patched 二进制"
echo "要立即更新已安装的 app，运行:"
echo "  cp \"$CACHE_DIR/sdl-freerdp\" \"/Applications/Ubuntu RDP.app/Contents/Resources/FreeRDP.app/Contents/MacOS/sdl-freerdp\""
echo "  codesign --force --deep --sign - \"/Applications/Ubuntu RDP.app\""
