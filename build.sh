#!/bin/bash
# 构建 DefaultApp.app 与 lsctl 测试 CLI，输出到 .build/
set -euo pipefail
cd "$(dirname "$0")"

APP="DefaultApp"
OUT=".build"
APP_DIR="$APP.app"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
ARCH="$(uname -m)"
TARGET="$ARCH-apple-macos14.0"

mkdir -p "$OUT"

echo "==> 生成应用图标"
swiftc -O -swift-version 5 -sdk "$SDK" -target "$TARGET" \
    -o "$OUT/icongen" \
    Sources/IconGen/main.swift
ICONSET="$OUT/$APP.iconset"
rm -rf "$ICONSET"
"$OUT/icongen" "$ICONSET"
iconutil -c icns -o "$OUT/$APP.icns" "$ICONSET"

echo "==> 编译 $APP"
# -swift-version 5：保持跨 SDK（macOS 14/15）一致的并发检查行为
swiftc -O -swift-version 5 -sdk "$SDK" -target "$TARGET" \
    -o "$OUT/$APP" \
    Sources/App/*.swift

echo "==> 编译 lsctl 测试 CLI"
swiftc -O -swift-version 5 -sdk "$SDK" -target "$TARGET" \
    -o "$OUT/lsctl" \
    Sources/App/LaunchServicesBridge.swift \
    Sources/TestCLI/main.swift

echo "==> 打包 $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
cp "$OUT/$APP" "$APP_DIR/Contents/MacOS/$APP"
cp "$OUT/$APP.icns" "$APP_DIR/Contents/Resources/$APP.icns"

mkdir -p "$APP_DIR/Contents/Resources/zh_CN.lproj"
cat > "$APP_DIR/Contents/Resources/zh_CN.lproj/InfoPlist.strings" <<'EOF'
"CFBundleName" = "默认打开方式";
"CFBundleDisplayName" = "默认打开方式";
EOF
mkdir -p "$APP_DIR/Contents/Resources/en.lproj"
cat > "$APP_DIR/Contents/Resources/en.lproj/InfoPlist.strings" <<'EOF'
"CFBundleName" = "Default Apps";
"CFBundleDisplayName" = "Default Apps";
EOF

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>DefaultApp</string>
    <key>CFBundleIconFile</key>
    <string>DefaultApp</string>
    <key>CFBundleIdentifier</key>
    <string>com.pt.DefaultApp</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>DefaultApp</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSHasLocalizedDisplayName</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP_DIR" 2>/dev/null || true

echo "==> 完成。运行: open \"$APP_DIR\""
