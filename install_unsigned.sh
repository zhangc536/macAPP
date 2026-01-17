#!/bin/bash

# 无证书应用快速安装脚本
# 用于解决 Gatekeeper 和权限问题

APP_NAME="YourApp"
APP_PATH="./build/$APP_NAME.app"
INSTALL_PATH="/Applications/$APP_NAME.app"

echo "================================"
echo "  $APP_NAME 快速安装工具"
echo "================================"
echo ""

# 检查应用是否存在
if [ ! -d "$APP_PATH" ]; then
    echo "❌ 错误: 未找到 $APP_PATH"
    echo "请先运行 ./build_app.sh 编译应用"
    exit 1
fi

echo "📦 找到应用: $APP_PATH"
echo ""

# 步骤 1: 移除隔离标志
echo "🔧 步骤 1/4: 移除隔离标志..."
xattr -cr "$APP_PATH" 2>/dev/null && echo "✅ 隔离标志已移除" || echo "⚠️  跳过（可能已移除）"
echo ""

# 步骤 2: Ad-hoc 签名
echo "🔧 步骤 2/4: 应用 Ad-hoc 签名..."
codesign --force --deep --sign - "$APP_PATH" 2>/dev/null && echo "✅ 签名完成" || echo "⚠️  签名失败（应用仍可运行）"
echo ""

# 步骤 3: 复制到 Applications（可选）
echo "🔧 步骤 3/4: 安装到 /Applications..."
read -p "是否安装到 /Applications? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    if [ -d "$INSTALL_PATH" ]; then
        echo "⚠️  应用已存在，正在替换..."
        rm -rf "$INSTALL_PATH"
    fi
    cp -R "$APP_PATH" "/Applications/" && echo "✅ 安装成功: $INSTALL_PATH" || {
        echo "❌ 安装失败（需要管理员权限）"
        echo "请手动复制: cp -R $APP_PATH /Applications/"
    }
    # 再次移除安装后的隔离标志
    xattr -cr "$INSTALL_PATH" 2>/dev/null
    APP_FINAL="$INSTALL_PATH"
else
    echo "⏭  跳过安装"
    APP_FINAL="$APP_PATH"
fi
echo ""

# 步骤 4: 验证签名
echo "🔧 步骤 4/4: 验证应用..."
echo "----------------------------------------"
codesign -dv "$APP_FINAL" 2>&1 | head -5
echo "----------------------------------------"
echo ""

# 检查架构
echo "🏗  架构信息:"
file "$APP_FINAL/Contents/MacOS/$APP_NAME" | grep -o "arm64\|x86_64" | tr '\n' ' '
echo ""
echo ""

# 完成提示
echo "================================"
echo "✅ 安装完成！"
echo "================================"
echo ""
echo "📝 首次运行说明:"
echo ""
echo "1️⃣  右键点击应用 → 选择'打开'"
echo "2️⃣  在弹出的警告中点击'打开'按钮"
echo "3️⃣  首次运行时授予以下权限:"
echo "   • 终端控制权限（必需）"
echo "   • 文件访问权限（推荐）"
echo "   • 完全磁盘访问权限（推荐）"
echo ""
echo "🚀 快速启动:"
echo "   open \"$APP_FINAL\""
echo ""
echo "📚 详细文档:"
echo "   cat docs/无证书使用指南.md"
echo ""

# 提供快速启动选项
read -p "是否现在启动应用? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🚀 正在启动..."
    open "$APP_FINAL"
    echo ""
    echo "⚠️  如果出现安全警告:"
    echo "   1. 打开 系统设置 → 隐私与安全性"
    echo "   2. 找到 '$APP_NAME' 的提示"
    echo "   3. 点击 '仍要打开'"
    echo "   4. 再次右键打开应用"
fi

echo ""
echo "🎉 祝您使用愉快！"
