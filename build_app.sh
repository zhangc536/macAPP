#!/bin/bash

# 编译脚本 - 用于构建和打包 macOS 应用

# 配置
APP_NAME="YourApp"
VERSION="1.0.6"
BUNDLE_ID="com.yourapp.YourApp"

# 清理旧构建产物
echo "Cleaning old build artifacts..."
rm -rf build/

# 编译多架构二进制（在部分环境可能只支持单架构，这里统一处理）
echo "Building multi-architecture binary..."
swift build -c release --arch arm64 --arch x86_64 || {
    echo "Multi-arch build failed, trying single-arch release build..."
    swift build -c release || {
        echo "❌ Swift build failed"
        exit 1
    }
}

# 创建 .app 目录结构
echo "Creating .app bundle structure..."
mkdir -p build/$APP_NAME.app/Contents/MacOS
mkdir -p build/$APP_NAME.app/Contents/Resources
mkdir -p build/$APP_NAME.app/Contents/Resources/scripts

# 复制编译产物
echo "Copying built executable..."

EXEC_SRC=""
if [ -f ".build/apple/Products/Release/$APP_NAME" ]; then
    EXEC_SRC=".build/apple/Products/Release/$APP_NAME"
elif [ -f ".build/release/$APP_NAME" ]; then
    EXEC_SRC=".build/release/$APP_NAME"
else
    echo "❌ Cannot find built executable for $APP_NAME"
    ls -R .build || true
    exit 1
fi

cp "$EXEC_SRC" "build/$APP_NAME.app/Contents/MacOS/$APP_NAME"

# 复制资源文件
echo "Copying resources..."
cp -r trae/Resources/* build/$APP_NAME.app/Contents/Resources/

# 创建 Info.plist
echo "Creating Info.plist..."
cat > build/$APP_NAME.app/Contents/Info.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>This app needs to control Terminal to display monitoring information.</string>
    <key>NSDesktopFolderUsageDescription</key>
    <string>This app needs access to the desktop folder for saving files.</string>
    <key>NSDocumentsFolderUsageDescription</key>
    <string>This app needs access to the documents folder for saving files.</string>
    <key>NSFullDiskAccessUsageDescription</key>
    <string>This app needs full disk access to monitor processes and files.</string>
    <key>NSSystemAdministrationUsageDescription</key>
    <string>This app needs administrator privileges for system tasks like installing Docker.</string>
    <key>LSUIElement</key>
    <false/>
    <key>CFBundleIconFile</key>
    <string></string>
    <key>NSAppleScriptEnabled</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>This app uses AppleScript to control Terminal for monitoring projects.</string>
    <key>com.apple.security.automation.apple-events</key>
    <true/>
</dict>
</plist>
EOF

# 创建 PkgInfo
echo "Creating PkgInfo..."
echo -n "APPL????" > build/$APP_NAME.app/Contents/PkgInfo

# 设置执行权限
echo "Setting executable permissions..."
chmod +x build/$APP_NAME.app/Contents/MacOS/$APP_NAME

# Ad-hoc 签名（无证书签名，避免某些系统检查问题）
echo "Applying ad-hoc code signature..."
codesign --force --deep --sign - build/$APP_NAME.app 2>/dev/null || {
    echo "⚠️  Warning: codesign not available or failed, app will run unsigned"
}

# 移除扩展属性（隔离标志），避免首次运行时的安全警告
echo "Removing quarantine attributes..."
xattr -cr build/$APP_NAME.app 2>/dev/null || {
    echo "⚠️  Warning: xattr not available"
}

# 验证构建
echo ""
echo "================================"
if [ -f "build/$APP_NAME.app/Contents/MacOS/$APP_NAME" ]; then
    echo "✅ Build successful!"
    echo "================================"
    echo "App bundle: build/$APP_NAME.app"
    echo ""
    echo "📦 无证书运行说明:"
    echo "1. 首次运行: 右键点击 $APP_NAME.app → 打开 → 点击'打开'按钮"
    echo "2. 或执行命令: open build/$APP_NAME.app"
    echo "3. 如遇到安全警告:"
    echo "   - 打开'系统设置' → '隐私与安全性'"
    echo "   - 找到被阻止的应用，点击'仍要打开'"
    echo ""
    echo "🔑 首次运行需要授权:"
    echo "   - 终端控制权限（AppleScript）"
    echo "   - 文件访问权限"
    echo "   - 管理员权限（部署操作时）"
    echo ""
    echo "🚀 快速测试: open build/$APP_NAME.app"
else
    echo "❌ Build failed: app executable not found"
    echo "Listing bundle contents for debugging:"
    ls -R build || true
    exit 1
fi
