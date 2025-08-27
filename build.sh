#!/bin/bash

set -e

echo "Building RateMate..."

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/RateMate.xcarchive"
APP_PATH="$BUILD_DIR/RateMate.app"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "Step 1: Building the app..."
xcodebuild -project "$PROJECT_DIR/RateMate.xcodeproj" \
    -scheme RateMate \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    -archivePath "$ARCHIVE_PATH" \
    archive

echo "Step 2: Exporting the app..."
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$BUILD_DIR" \
    -exportOptionsPlist "$PROJECT_DIR/ExportOptions.plist"

echo ""
echo "Build complete! App located at: $APP_PATH"
echo ""
echo "To run the app:"
echo "  open '$APP_PATH'"
echo ""
echo "Note: You'll need to grant Full Disk Access to RateMate:"
echo "  1. Open System Settings → Privacy & Security → Full Disk Access"
echo "  2. Add RateMate to the list and enable it"
echo "  3. Restart RateMate"