#!/bin/bash
# 打包 DefaultApp.app 为可分发的 DMG（含「应用程序」快捷方式）
set -e
cd "$(dirname "$0")"

APP="DefaultApp.app"
[ -d "$APP" ] || { echo "先运行 ./build.sh"; exit 1; }

STAGE="/tmp/defaultapp-dmg"
OUT="DefaultApp.dmg"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$OUT"
hdiutil create -volname "DefaultApp" -srcfolder "$STAGE" \
    -ov -format UDZO "$OUT" >/dev/null
rm -rf "$STAGE"

echo "==> 完成: $OUT"
echo "    对方打开 DMG 后把 DefaultApp 拖入「应用程序」即可"
