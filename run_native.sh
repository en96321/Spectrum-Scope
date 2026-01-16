#!/bin/bash

# 定義路徑
# 定義路徑
PROJECT="macos/Runner.xcodeproj"
SCHEME="Runner"
CONFIG="Debug"
BUILD_DIR="build_native"

echo "🚀 正在編譯 Audio Scope (Native Swift)..."

# 使用 xcodebuild 進行編譯
# -quiet: 減少輸出，只顯示警告和錯誤
# -derivedDataPath: 指定輸出目錄，方便找到 App
# 清理舊的編譯檔案以確保更名生效
rm -rf "$BUILD_DIR"

xcodebuild -project "$PROJECT" \
           -scheme "$SCHEME" \
           -configuration "$CONFIG" \
           -derivedDataPath "$BUILD_DIR" \
           PRODUCT_NAME="Spectrum Scope" \
           -quiet

# 檢查編譯結果
if [ $? -eq 0 ]; then
    echo "✅ 編譯成功！正在啟動..."
    
    # 尋找原始編譯產物
    OLD_APP_PATH="$BUILD_DIR/Build/Products/$CONFIG/audio_scope.app"
    APP_PATH="$BUILD_DIR/Build/Products/$CONFIG/Spectrum Scope.app"
    
    if [ -d "$OLD_APP_PATH" ]; then
        # 如果存在舊名 App，更名為 Spectrum Scope
        echo "✨ Renaming App bundle to Spectrum Scope..."
        rm -rf "$APP_PATH" # 移除舊的目標 (如果有的話)
        mv "$OLD_APP_PATH" "$APP_PATH"
    fi

    if [ -d "$APP_PATH" ]; then
        # 5. 執行 App
        echo "📝 提示：若要查看 Log，請在另一個終端機執行："
        echo "   xcrun simctl spawn booted log stream --predicate 'process == \"Runner\"'"
        echo "   (註：如果是本機執行，請直接使用 Console.app 或 /usr/bin/log)"
        
        # 注意：雖然 App Bundle 改名了，但內部的與可執行檔通常還是原名 (unless project settings changed)
        # 這裡我們嘗試尋找可執行檔
        EXECUTABLE_NAME="audio_scope"
        if [ ! -f "$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME" ]; then
             EXECUTABLE_NAME="Spectrum Scope"
        fi
        
        "$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME"
    else
        echo "❌ 找不到 App 檔案：$APP_PATH (or $OLD_APP_PATH)"
    fi
else
    echo "❌ 編譯失敗"
    exit 1
fi
