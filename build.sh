#!/bin/bash
# build.sh — 构建 Ubuntu RDP 客户端 .app
# 用法：
#   ./build.sh           # 构建到 build/
#   ./build.sh install   # 构建并安装到 /Applications
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Ubuntu RDP"
EXECUTABLE="Ubuntu-RDP"
APP_BUNDLE="$APP_NAME.app"
BUILD_DIR="$PROJECT_DIR/build"
APP_PATH="$BUILD_DIR/$APP_BUNDLE"

echo "=== 编译 Swift 源码 ==="
mkdir -p "$BUILD_DIR"

# 编译所有 .swift 文件
swiftc \
    "$PROJECT_DIR"/Sources/*.swift \
    -framework Cocoa \
    -O \
    -o "$BUILD_DIR/$EXECUTABLE"

echo "=== 打包 .app ==="
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"

cp "$BUILD_DIR/$EXECUTABLE" "$APP_PATH/Contents/MacOS/$EXECUTABLE"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"
cp "$PROJECT_DIR/Resources/Ubuntu.icns" "$APP_PATH/Contents/Resources/Ubuntu.icns"

chmod +x "$APP_PATH/Contents/MacOS/$EXECUTABLE"

# 刷新图标缓存
touch "$APP_PATH"

echo ""
echo "=== 构建完成 ✓ ==="
echo "位置: $APP_PATH"
echo ""
echo "运行: open \"$APP_PATH\""
echo "安装到 /Applications: ./build.sh install"

# 可选：安装
if [ "$1" = "install" ]; then
    echo ""
    echo "=== 安装到 /Applications ==="
    rm -rf "/Applications/$APP_BUNDLE"
    cp -R "$APP_PATH" "/Applications/"
    echo "已安装到 /Applications/$APP_BUNDLE"
fi
