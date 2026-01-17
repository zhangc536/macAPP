#!/bin/bash

# DMG 打包脚本 - 用于创建 macOS 应用安装包

# 配置
APP_NAME="YourApp"
VERSION="1.0.0"

# 确保 create-dmg 已安装
if ! command -v create-dmg &> /dev/null; then
    echo "create-dmg not found. Installing..."
    brew install create-dmg
fi

# 清理旧 DMG
echo "Cleaning old DMG..."
rm -f $APP_NAME.dmg

# 检查.app文件是否存在
if [ ! -d "../build/$APP_NAME.app" ]; then
    echo "Error: ../build/$APP_NAME.app not found. Please run build_app.sh first."
    exit 1
fi

# 创建 DMG
echo "Creating DMG installer..."
create-dmg \
  --volname "$APP_NAME Installer" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --app-drop-link 500 200 \
  --hide-extension "$APP_NAME.app" \
  --icon-size 100 \
  --icon "$APP_NAME.app" 100 200 \
  --background "../trae/Resources/background.png" \
  --text-size 12 \
  --add-file "../docs/README.md" "README.md" 100 300 \
  ../build/$APP_NAME.app \
  .

# 验证 DMG
echo "Verifying DMG..."
if [ -f "$APP_NAME.dmg" ]; then
    echo "✅ DMG created successfully: $APP_NAME.dmg"
    echo "Size: $(du -h $APP_NAME.dmg | cut -f1)"
    echo "SHA256: $(shasum -a 256 $APP_NAME.dmg | cut -d' ' -f1)"
else
    echo "❌ DMG creation failed!"
    exit 1
fi
