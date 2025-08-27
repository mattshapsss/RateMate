#!/bin/bash

set -e

# Configuration
APP_NAME="RateMate"
BUNDLE_ID="com.example.ratemate"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
APP_PATH="$BUILD_DIR/$APP_NAME.app"
DMG_PATH="$BUILD_DIR/$APP_NAME.dmg"
ZIP_PATH="$BUILD_DIR/$APP_NAME.zip"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}RateMate Notarization Script${NC}"
echo "======================================"

# Check for required tools
if ! command -v xcrun &> /dev/null; then
    echo -e "${RED}Error: Xcode command line tools not installed${NC}"
    exit 1
fi

# Check for credentials
if [ -z "$APPLE_ID" ]; then
    echo -e "${YELLOW}APPLE_ID environment variable not set${NC}"
    read -p "Enter your Apple ID: " APPLE_ID
fi

if [ -z "$TEAM_ID" ]; then
    echo -e "${YELLOW}TEAM_ID environment variable not set${NC}"
    read -p "Enter your Team ID: " TEAM_ID
fi

if [ -z "$APP_PASSWORD" ]; then
    echo -e "${YELLOW}APP_PASSWORD environment variable not set${NC}"
    echo "Create an app-specific password at appleid.apple.com"
    read -s -p "Enter app-specific password: " APP_PASSWORD
    echo
fi

# Step 1: Build Release Archive
echo -e "\n${GREEN}Step 1: Building Release Archive${NC}"
xcodebuild -project "$PROJECT_DIR/RateMate.xcodeproj" \
    -scheme RateMate \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    clean archive \
    CODE_SIGN_STYLE="Automatic" \
    DEVELOPMENT_TEAM="$TEAM_ID"

# Step 2: Export Archive
echo -e "\n${GREEN}Step 2: Exporting Archive${NC}"

# Create export options with team ID
cat > "$BUILD_DIR/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
EOF

xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$BUILD_DIR" \
    -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist"

# Step 3: Create ZIP for notarization
echo -e "\n${GREEN}Step 3: Creating ZIP for notarization${NC}"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

# Step 4: Submit for notarization
echo -e "\n${GREEN}Step 4: Submitting for notarization${NC}"
xcrun notarytool submit "$ZIP_PATH" \
    --apple-id "$APPLE_ID" \
    --team-id "$TEAM_ID" \
    --password "$APP_PASSWORD" \
    --wait \
    --verbose

# Step 5: Staple the notarization
echo -e "\n${GREEN}Step 5: Stapling notarization${NC}"
xcrun stapler staple "$APP_PATH"

# Step 6: Create DMG for distribution
echo -e "\n${GREEN}Step 6: Creating DMG for distribution${NC}"

# Create a temporary directory for DMG contents
DMG_TEMP="$BUILD_DIR/dmg-temp"
rm -rf "$DMG_TEMP"
mkdir -p "$DMG_TEMP"

# Copy app to DMG temp
cp -R "$APP_PATH" "$DMG_TEMP/"

# Create Applications symlink
ln -s /Applications "$DMG_TEMP/Applications"

# Create DMG
hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_TEMP" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

# Clean up temp directory
rm -rf "$DMG_TEMP"

# Step 7: Verify notarization
echo -e "\n${GREEN}Step 7: Verifying notarization${NC}"
spctl -a -vvv -t install "$APP_PATH"
xcrun stapler validate "$APP_PATH"

# Summary
echo -e "\n${GREEN}======================================"
echo -e "✅ Notarization Complete!${NC}"
echo -e "${GREEN}======================================${NC}"
echo ""
echo "Signed and notarized app: $APP_PATH"
echo "Distribution DMG: $DMG_PATH"
echo ""
echo "To distribute:"
echo "1. Upload $DMG_PATH to your distribution channel"
echo "2. Users can drag RateMate to Applications folder"
echo "3. First launch will verify notarization"
echo ""
echo -e "${YELLOW}Remember:${NC}"
echo "- Users need to grant Full Disk Access after installation"
echo "- The app is not sandboxed (required for OSLog access)"
echo "