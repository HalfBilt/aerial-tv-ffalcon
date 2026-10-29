#!/usr/bin/env bash
# 雷鸟专用版自检：一次跑完，看 5 件事有没有被固件改回去。
#
#   ./tools/verify-tcl.sh 192.168.100.72
#
# 用法：第一个参数是电视 IP（默认 192.168.100.72），ADB 用 $ADB 或 PATH 里的 adb。
# 全部通过时最后一行打印 OK；有任何一条不对，打印 FAIL 并列出是哪条。

set -u

TV="${1:-192.168.100.72}"
ADB="${ADB:-adb}"
PKG=app.orchard.tv
GUARD="$PKG/$PKG.guard.HomeGuardService"

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }
val() { "$ADB" shell "$1" 2>/dev/null | tr -d '\r'; }

fails=()

"$ADB" connect "$TV:5555" >/dev/null 2>&1

state=$("$ADB" get-state 2>/dev/null | tr -d '\r')
if [ "$state" != "device" ]; then
  echo "电视没连上（get-state=$state）。确认电视开着、ADB 调试没关，再跑一次。" >&2
  exit 2
fi

say "1. 装的版本"
v=$(val "dumpsys package $PKG | grep versionName")
echo "   $v"
case "$v" in
  *versionName=*) ;;
  *) fails+=("没装上 / 包名不对") ;;
esac

say "2. 默认桌面（系统解析出来的）"
h=$(val "cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME -c android.intent.category.DEFAULT" | tail -1)
echo "   $h"
case "$h" in
  "$PKG"/*) ;;
  *) fails+=("默认桌面不是 Aerial（$h）：跑 cmd package set-home-activity --user 0 $PKG/.MainActivity") ;;
esac

say "3. TCL 的开机启动项（固件会无视默认桌面，只看这个）"
b=$(val "settings get system boot_app_componentname")
m=$(val "settings get system boot_app_mode")
echo "   boot_app_componentname = $b"
echo "   boot_app_mode          = $m"
case "$b" in
  "$PKG"/*) ;;
  *) fails+=("开机启动项不是 Aerial（$b）：跑 settings put system boot_app_componentname $PKG/.MainActivity") ;;
esac

say "4. 无障碍服务（TCL 自己的必须还在）"
a=$(val "settings get secure enabled_accessibility_services")
echo "   $a"
case "$a" in
  *"$GUARD"*) ;;
  *) fails+=("守护不在无障碍列表里：Aerial 启动一次会自己加回来，或手动 settings put") ;;
esac
case "$a" in
  *com.tcl.*) ;;
  *) fails+=("TCL 自己的无障碍服务不见了（$a）——这会弄坏「小T助手」") ;;
esac

say "5. 守护真的在跑吗"
n=$(val "dumpsys accessibility | grep -c -E 'label=(Aerial|app.orchard.tv)'")
echo "   dumpsys accessibility 命中 $n 条"
if [ "${n:-0}" -gt 0 ] 2>/dev/null; then :; else
  fails+=("守护没在跑（命中 0 条）：am force-stop $PKG 后重新打开 Aerial")
fi

say "6. 现在前台是谁"
f=$(val "dumpsys window | grep mCurrentFocus")
echo "   $f"

say "附：最近的诊断日志（最后 20 行）"
"$ADB" shell "dumpsys activity $PKG/.MainActivity" 2>/dev/null | tail -20 | sed 's/^/   /'

echo
if [ ${#fails[@]} -eq 0 ]; then
  echo "OK — 6 项全过"
  exit 0
fi
echo "FAIL — ${#fails[@]} 项要处理："
for f in "${fails[@]}"; do echo "  - $f"; done
exit 1
