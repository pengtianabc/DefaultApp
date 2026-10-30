#!/bin/bash
# 构建 DefaultApp.app 与 defaultapp 命令行工具，输出到 .build/
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

echo "==> 编译 defaultapp 命令行工具"
# 注意：必须放在 cli/ 子目录。APFS 默认大小写不敏感，.build/DefaultApp（App 二进制）
# 与 .build/defaultapp（CLI）会互相覆盖，导致 .app 里的可执行文件被换成 CLI。
mkdir -p "$OUT/cli"
swiftc -O -swift-version 5 -sdk "$SDK" -target "$TARGET" \
    -o "$OUT/cli/defaultapp" \
    Sources/App/LaunchServicesBridge.swift \
    Sources/App/ExtensionCatalog.swift \
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
    <string>1.0.1</string>
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

# 保险：.app 的可执行文件必须是 GUI（链接 SwiftUI）。防止构建目录中的
# 命名冲突（如大小写不敏感磁盘上 DefaultApp/defaultapp 互相覆盖）无声进入产物。
if ! otool -L "$APP_DIR/Contents/MacOS/$APP" | grep -q SwiftUI; then
    echo "!! $APP_DIR 的可执行文件缺少 SwiftUI 链接（疑似被 CLI 覆盖），中止" >&2
    exit 1
fi

codesign --force --sign - "$APP_DIR" 2>/dev/null || true

echo "==> 完成。运行: open \"$APP_DIR\""
