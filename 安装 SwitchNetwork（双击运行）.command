#!/bin/bash
#
# SwitchNetwork 安装辅助：把 app 装进「应用程序」，并清掉它的隔离属性。
#
# 双击运行；也可以把 SwitchNetwork.app 拖到本文件上再运行。
#
# 做的事：
#   1. app 还在只读的 dmg 里时，问一句就把整份拷进「应用程序」；
#   2. 删掉 com.apple.quarantine，让没有开发者签名的 app 双击能直接打开。
# 不改 app 的内容，也不动任何系统设置。
#
# 目标 app 的查找顺序：拖进来的 > /Applications 里已安装的 > 脚本同目录的。

set -u

APP_NAME="SwitchNetwork.app"
INSTALL_PATH="/Applications/$APP_NAME"
XATTR_BIN="/usr/bin/xattr"
SUDO_BIN="/usr/bin/sudo"
GREP_BIN="/usr/bin/grep"
RM_BIN="/bin/rm"
DITTO_BIN="/usr/bin/ditto"
PGREP_BIN="/usr/bin/pgrep"
OSASCRIPT_BIN="/usr/bin/osascript"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

pause() {
    echo
    read -r -p "按回车键关闭窗口…" _
}

# 数一数 app 里还有几处带隔离属性。-r 递归，-l 列出属性名。
count_quarantine() {
    "$XATTR_BIN" -r -l "$1" 2>/dev/null | "$GREP_BIN" -c "com.apple.quarantine"
}

echo "=============================================="
echo "  SwitchNetwork 安装"
echo "=============================================="
echo

APP=""
if [ "$#" -ge 1 ]; then
    APP="$1"
elif [ -d "$INSTALL_PATH" ]; then
    APP="$INSTALL_PATH"
elif [ -d "$SCRIPT_DIR/$APP_NAME" ]; then
    APP="$SCRIPT_DIR/$APP_NAME"
fi

if [ -z "$APP" ] || [ ! -d "$APP" ]; then
    echo "找不到 ${APP_NAME}。"
    echo "请把它拖到本脚本上再运行，或者先拖进「应用程序」。"
    pause
    exit 1
fi

echo "找到：$APP"
echo

# dmg 挂载出来的是只读卷，改不了属性，先把整份装进「应用程序」再处理。
# 已经在 /Applications 里、只是当前用户写不进去的情况不走这一步，交给下面的 sudo。
if [ "$APP" != "$INSTALL_PATH" ] && [ ! -w "$(dirname "$APP")" ]; then
    echo "这个 app 还在只读的磁盘映像里，先安装到「应用程序」。"
    if [ -d "$INSTALL_PATH" ]; then
        echo "注意：$INSTALL_PATH 已经存在，会被这一份覆盖。"
    fi
    echo
    ANSWER=""
    read -r -p "继续请输入 y，其他键取消：" ANSWER
    case "$ANSWER" in
        y|Y) ;;
        *)
            echo "已取消，什么都没做。"
            pause
            exit 0
            ;;
    esac
    echo

    # 旧版本还开着的话先让它退出，否则覆盖的是它正在用的 bundle。
    if "$PGREP_BIN" -x "SwitchNetwork" >/dev/null 2>&1; then
        echo "先退掉正在运行的 SwitchNetwork…"
        "$OSASCRIPT_BIN" -e 'tell application "SwitchNetwork" to quit' >/dev/null 2>&1
        sleep 1
    fi

    "$RM_BIN" -rf "$INSTALL_PATH"
    if ! "$DITTO_BIN" "$APP" "$INSTALL_PATH"; then
        echo
        echo "拷贝失败：写不进「应用程序」，或者这个 app 不完整。"
        pause
        exit 1
    fi
    echo "已安装到 $INSTALL_PATH"
    APP="$INSTALL_PATH"
fi

echo
BEFORE="$(count_quarantine "$APP")"

if [ "$BEFORE" = "0" ]; then
    echo "没有隔离属性，不需要处理。"
    echo "（隔离属性是下载工具打上的，本机自己编译、直接拷贝过来的 app 本来就没有。）"
else
    echo "发现 $BEFORE 处隔离属性，开始清除。"
    echo "接下来会要求输入开机密码，这是 sudo 在用，输入时屏幕上不显示字符。"
    echo
    if ! "$SUDO_BIN" "$XATTR_BIN" -rd com.apple.quarantine "$APP"; then
        echo
        echo "清除失败：密码不对，或者这个 app 不属于当前用户。"
        pause
        exit 1
    fi
    echo
    AFTER="$(count_quarantine "$APP")"
    if [ "$AFTER" = "0" ]; then
        echo "已清除干净，隔离属性一处不剩。"
    else
        echo "还剩 $AFTER 处没清掉，再运行一次本脚本试试。"
    fi
fi

echo
echo "----------------------------------------------"
echo "装好了。到「应用程序」里双击 SwitchNetwork 就能打开。"
echo
echo "万一 Finder 还提示「无法验证开发者」："
echo "  右键（或按住 Control 点击）app → 打开 → 在弹窗里再点一次「打开」。"
echo "  只需做一次，之后双击就正常了。"
echo "----------------------------------------------"
pause
