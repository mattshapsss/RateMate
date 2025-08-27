#!/bin/bash

set -e

echo "Building RateMate (Debug)..."

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/build"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "Building with xcodebuild..."
xcodebuild -project "$PROJECT_DIR/RateMate.xcodeproj" \
    -scheme RateMate \
    -configuration Debug \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    build

APP_PATH=$(find "$BUILD_DIR" -name "RateMate.app" -type d | head -1)

if [ -z "$APP_PATH" ]; then
    echo "Error: Could not find built app"
    exit 1
fi

cp -r "$APP_PATH" "$BUILD_DIR/RateMate.app"

echo ""
echo "Build complete! App located at: $BUILD_DIR/RateMate.app"
echo ""
echo "To run the app:"
echo "  open '$BUILD_DIR/RateMate.app'"
echo ""
echo "IMPORTANT: First-time setup:"
echo "  1. Run the app once - it will show a permission dialog"
echo "  2. Open System Settings → Privacy & Security → Full Disk Access"
echo "  3. Click the + button and add RateMate.app"
echo "  4. Enable the toggle for RateMate"
echo "  5. Restart RateMate for changes to take effect"