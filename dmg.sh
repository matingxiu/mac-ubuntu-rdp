#!/bin/bash
# dmg.sh — 把 Ubuntu RDP 打包成 DMG 安装包
# 用法：./dmg.sh
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Ubuntu RDP"
APP_BUNDLE="$APP_NAME.app"
BUILD_DIR="$PROJECT_DIR/build"
APP_PATH="$BUILD_DIR/$APP_BUNDLE"

# 版本号：优先用 git tag，否则默认 1.0.0
VERSION=$(git -C "$PROJECT_DIR" describe --tags --abbrev=0 2>/dev/null || echo "1.0.0")
DMG_NAME="Ubuntu-RDP-$VERSION.dmg"
DMG_PATH="$BUILD_DIR/$DMG_NAME"
STAGING_DIR="$BUILD_DIR/dmg-staging"
TMP_DMG="$BUILD_DIR/tmp-rw.dmg"

echo "=== 版本: $VERSION ==="

echo ""
echo "=== 步骤 1/5:构建 .app ==="
"$PROJECT_DIR/build.sh"

echo ""
echo "=== 步骤 2/5:准备 DMG 暂存目录 ==="
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

echo ""
echo "=== 步骤 3/5:创建可读写 DMG ==="
rm -f "$TMP_DMG" "$DMG_PATH"
hdiutil create -volname "$APP_NAME" \
    -srcfolder "$STAGING_DIR" \
    -fs HFS+ \
    -format UDRW \
    "$TMP_DMG"

echo ""
echo "=== 步骤 4/5:挂载并美化布局 ==="
MOUNT_INFO=$(hdiutil attach -readwrite -noverify -noautoopen "$TMP_DMG")
# 卷名含空格，用 grep -o 提取完整 /Volumes/ 路径（不能用 awk 按空格切分）
MOUNT_POINT=$(echo "$MOUNT_INFO" | grep -o '/Volumes/.*' | head -1)
echo "挂载点: $MOUNT_POINT"

# 用 Finder 设置图标视图和位置（App 左、Applications 右）
osascript <<OSA 2>/dev/null || echo "（布局美化跳过，不影响 DMG）"
tell application "Finder"
    tell disk "$APP_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {100, 100, 600, 420}
        set view options of icon view of container window to {arrangement:arranged not in name, icon size:96}
        set position of item "$APP_NAME" of container window to {130, 160}
        set position of item "Applications" of container window to {370, 160}
        close
    end tell
end tell
OSA

echo ""
echo "=== 步骤 5/5:卸载并转换为只读压缩 DMG ==="
hdiutil detach "$MOUNT_POINT"
hdiutil convert "$TMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH"
rm -f "$TMP_DMG"
rm -rf "$STAGING_DIR"

echo ""
echo "=== DMG 打包完成 ✓ ==="
echo "文件: $DMG_PATH"
echo "大小: $(du -h "$DMG_PATH" | cut -f1)"
echo ""
echo "可直接分发或上传到 GitHub Release。"
