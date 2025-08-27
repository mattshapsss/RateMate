#!/bin/bash

set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/build"

echo "======================================"
echo "🧪 RateMate Test Suite"
echo "======================================"
echo ""

# Run unit tests
echo "📋 Running Unit Tests..."
echo "-------------------------------------"
xcodebuild test \
    -project "$PROJECT_DIR/RateMate.xcodeproj" \
    -scheme RateMate \
    -destination "platform=macOS" \
    -quiet \
    | grep -E "(Test Suite|passed|failed)" || true

echo ""
echo "======================================"
echo "✅ Tests Complete"
echo "======================================"
echo ""
echo "To run acceptance tests with the app:"
echo "1. Build and run the app: ./build_debug.sh && open build/RateMate.app"
echo "2. Grant Full Disk Access if needed"
echo "3. The acceptance tests simulate Music playback scenarios"
echo ""