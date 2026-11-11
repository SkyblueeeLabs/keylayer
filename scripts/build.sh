#!/bin/bash
# build.sh — 从源码构建 CLI 与菜单栏 App（含图标生成与签名）
#
# 用法（在项目根目录）：
#   bash scripts/build.sh
#
# 用环境变量覆盖输出路径，可在不触碰现有 App 的情况下验证构建：
#   KEYMAP_APP=/tmp/Test.app KEYMAP_CLI=/tmp/km-cli bash scripts/build.sh
set -euo pipefail
cd "$(dirname "$0")/.."

APP="${KEYLAYER_APP:-KeyLayer.app}"
CLI="${KEYLAYER_CLI:-KeyLayer}"
# 相对路径要补全，否则执行时不会查当前目录
case "$CLI" in
    /*) CLI_PATH="$CLI" ;;
    *)  CLI_PATH="$PWD/$CLI" ;;
esac
CERT="KeyLayer Local Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
ICONSET="assets/icons/AppIcon.iconset"

echo "[0/5] 从共享规格生成三端代码"
node scripts/gen-sources.mjs

echo "[1/5] 生成图标资源"
swift scripts/gen-icons.swift
mkdir -p "$ICONSET" "$APP/Contents/MacOS" "$APP/Contents/Resources"
# 128px 以下用无字标的紧凑版，避免文字在 Dock/Finder 小尺寸下糊掉
SMALL_ICON="assets/icons/AppIcon-small-1024.png"
FULL_ICON="assets/icons/AppIcon-1024.png"
make_icon() {
    sips -Z "$1" "$3" --out "$ICONSET/$2" >/dev/null
}
make_icon 16   icon_16x16.png      "$SMALL_ICON"
make_icon 32   icon_16x16@2x.png   "$SMALL_ICON"
make_icon 32   icon_32x32.png      "$SMALL_ICON"
make_icon 64   icon_32x32@2x.png   "$SMALL_ICON"
make_icon 128  icon_128x128.png    "$FULL_ICON"
make_icon 256  icon_128x128@2x.png "$FULL_ICON"
make_icon 256  icon_256x256.png    "$FULL_ICON"
make_icon 512  icon_256x256@2x.png "$FULL_ICON"
make_icon 512  icon_512x512.png    "$FULL_ICON"
make_icon 1024 icon_512x512@2x.png "$FULL_ICON"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
cp assets/icons/MenuIcon.png assets/icons/MenuIcon@2x.png "$APP/Contents/Resources/"

echo "[2/5] 构建命令行版"
swiftc -O src/KeyLayerCore.swift src/Generated.swift src/KeyLayerCLI.swift -o "$CLI"

echo "[3/5] 构建菜单栏 App"
swiftc -O src/KeyLayerCore.swift src/Generated.swift src/GeneratedTokens.swift src/KeyLayerApp.swift -o "$APP/Contents/MacOS/KeyLayer"
cp src/Info.plist "$APP/Contents/Info.plist"

echo "[4/5] 签名"
rm -rf "$APP/Contents/_CodeSignature"
if security find-certificate -c "$CERT" "$KEYCHAIN" >/dev/null 2>&1; then
    # 证书签名偶尔因钥匙串交互挂起，加超时后回退 ad-hoc，保证构建不阻塞
    if python3 - "$CERT" "$APP" <<'PY'
import subprocess, sys
cert, app = sys.argv[1], sys.argv[2]
try:
    r = subprocess.run(["codesign", "--force", "--sign", cert, app],
                       capture_output=True, text=True, timeout=15)
    sys.exit(r.returncode)
except subprocess.TimeoutExpired:
    subprocess.run(["pkill", "-x", "codesign"])
    sys.exit(124)
PY
    then
        echo "  稳定证书签名（重建不丢授权）"
    else
        echo "  [警告] 证书签名未完成，回退 ad-hoc"
        codesign --force --sign - "$APP"
    fi
else
    echo "  [提示] 未找到 $CERT，使用 ad-hoc 签名"
    echo "  建议先运行：bash scripts/fix-permissions.sh"
    codesign --force --sign - "$APP"
fi
codesign -dr - "$APP" 2>&1 | tail -1
codesign --verify --deep --strict "$APP"

echo "[5/5] 自测"
"$CLI_PATH" --self-test | tail -2

echo ""
case "$APP" in
    /*) APP_PATH="$APP" ;;
    *)  APP_PATH="$PWD/$APP" ;;
esac

echo "完成："
echo "  自测   $CLI_PATH --self-test"
echo "  调试   $CLI_PATH --debug"
echo "  启动   open \"$APP_PATH\""
echo ""
echo "首次运行需在 系统设置 → 隐私与安全性 → 设备控制与数据访问 / 输入监控 中授权"
echo "命令行版与 App 版不要同时运行。"
