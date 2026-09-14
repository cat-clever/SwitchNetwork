#!/bin/bash
#
# 打包成 dmg：里面放 app、安装脚本，以及指向「应用程序」的替身，
# 跟常见 macOS 应用一样：打开 dmg → 把 app 拖进「应用程序」→
# 双击里面的「安装 SwitchNetwork（双击运行）.command」清掉隔离属性。
#
# 用法：./make_dmg.sh [Debug|Release] [额外的 build settings...]
#       不传配置就用 Release；
#       后面的额外参数原样传给 xcodebuild，CI 用它传签名参数，
#       比如：./make_dmg.sh Release CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=-
#
# 产物名带版本号（版本号读 Config/SwitchNetwork.xcconfig，改一处即可）。
# 中间产物 dmg-stage/ 和 dmg 都放在本目录（不放 /tmp）。

set -euo pipefail

CONFIG="${1:-Release}"
shift || true

EXTRA_SETTINGS=()
if [ "$#" -gt 0 ]; then
    EXTRA_SETTINGS=("$@")
fi

APP_NAME="SwitchNetwork.app"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
STAGE_DIR="$PROJECT_DIR/dmg-stage"
XCCONFIG="$PROJECT_DIR/Config/SwitchNetwork.xcconfig"
INSTALLER_SCRIPT="$PROJECT_DIR/安装 SwitchNetwork（双击运行）.command"
DEVELOPER_DIR_OVERRIDE=""

if ! XCODEBUILD="$(xcrun --find xcodebuild 2>/dev/null)" || [ ! -x "$XCODEBUILD" ]; then
    # 本机把开发者目录切成了命令行工具时，xcrun 找不到 xcodebuild，
    # 直接退回装好的 Xcode，不要求用户先跑 sudo xcode-select。
    if [ -x /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild ]; then
        XCODEBUILD=/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild
        DEVELOPER_DIR_OVERRIDE=/Applications/Xcode.app/Contents/Developer
        echo "提示：系统当前选中的开发者目录不是 Xcode，本次改用 $DEVELOPER_DIR_OVERRIDE"
    else
        echo "找不到 xcodebuild。装好 Xcode 后执行一次：sudo xcode-select -s /Applications/Xcode.app"
        exit 1
    fi
fi

# 用回退路径时得把 DEVELOPER_DIR 一起带上，否则工具链仍会解析到命令行工具。
run_xcodebuild() {
    if [ -n "$DEVELOPER_DIR_OVERRIDE" ]; then
        DEVELOPER_DIR="$DEVELOPER_DIR_OVERRIDE" "$XCODEBUILD" "$@"
    else
        "$XCODEBUILD" "$@"
    fi
}
if [ ! -f "$XCCONFIG" ]; then
    echo "找不到版本配置文件：$XCCONFIG"
    exit 1
fi
if [ ! -f "$INSTALLER_SCRIPT" ]; then
    echo "找不到安装脚本：$INSTALLER_SCRIPT"
    exit 1
fi

# 版本号从 xcconfig 里读，保证 dmg 名字、app 里的版本号是同一个来源。
VERSION="$(awk -F'=' '/^[[:space:]]*MARKETING_VERSION[[:space:]]*=/ {gsub(/[[:space:]]/, "", $2); print $2; exit}' "$XCCONFIG")"
if [ -z "$VERSION" ]; then
    echo "$XCCONFIG 里没读到 MARKETING_VERSION"
    exit 1
fi
DMG_PATH="$PROJECT_DIR/SwitchNetwork-$VERSION.dmg"

cd "$PROJECT_DIR"

# xcodebuild 会把 CLI 传的 build setting 覆盖在 xcconfig 之上，
# 所以这里透传的签名参数能盖住项目里 Automatic 的设置。
XCODEBUILD_ARGS=(
    -project SwitchNetwork.xcodeproj
    -scheme SwitchNetwork
    -configuration "$CONFIG"
    -destination 'platform=macOS'
)

echo "== 1/4 编译（${CONFIG}，版本 ${VERSION}）=="
if [ "${#EXTRA_SETTINGS[@]}" -gt 0 ]; then
    echo "   额外设置：${EXTRA_SETTINGS[*]}"
fi
run_xcodebuild "${XCODEBUILD_ARGS[@]}" ${EXTRA_SETTINGS[@]+"${EXTRA_SETTINGS[@]}"} build

echo
echo "== 2/4 定位产物 =="
BUILD_DIR="$(run_xcodebuild "${XCODEBUILD_ARGS[@]}" ${EXTRA_SETTINGS[@]+"${EXTRA_SETTINGS[@]}"} \
    -showBuildSettings 2>/dev/null | awk -F' = ' '/BUILT_PRODUCTS_DIR/ {print $2; exit}')"
APP_PATH="$BUILD_DIR/$APP_NAME"

if [ ! -d "$APP_PATH" ]; then
    echo "编译完了但找不到 app：$APP_PATH"
    exit 1
fi
echo "   $APP_PATH"

# 编译产物里的版本号必须和 xcconfig 对上，免得发出去的 dmg 名字和内容不一致。
BUILT_VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP_PATH/Contents/Info.plist" 2>/dev/null || true)"
if [ "$BUILT_VERSION" != "$VERSION" ]; then
    echo "版本对不上：xcconfig 是 ${VERSION}，app 里是 ${BUILT_VERSION:-读不到}"
    echo "多半是 project.pbxproj 里又写回了 MARKETING_VERSION，它会把 xcconfig 盖掉。"
    exit 1
fi
echo "   app 内版本号 ${BUILT_VERSION}，与配置一致"

echo
echo "== 3/4 准备 dmg 内容 =="
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
ditto "$APP_PATH" "$STAGE_DIR/$APP_NAME"
cp "$INSTALLER_SCRIPT" "$STAGE_DIR/"
chmod 755 "$STAGE_DIR/$(basename "$INSTALLER_SCRIPT")"
ln -s /Applications "$STAGE_DIR/Applications"
echo "   $(ls -1 "$STAGE_DIR" | tr '\n' ' ')"

echo
echo "== 4/4 生成 dmg =="
rm -f "$DMG_PATH"
hdiutil create \
    -volname "SwitchNetwork" \
    -srcfolder "$STAGE_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

rm -rf "$STAGE_DIR"

echo
echo "完成：$DMG_PATH"
ls -lh "$DMG_PATH"
echo
echo "提示：dmg 第一次被下载时整个会被打上隔离属性，里面的 .command 也会被牵连。"
echo "     如果双击脚本时 Finder 拦住它自己，右键 → 打开，让它跑一次就行。"
