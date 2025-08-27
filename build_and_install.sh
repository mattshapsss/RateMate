#!/bin/bash

# RateMate Build and Install Script
# This script builds RateMate in Release mode and installs it to /Applications

set -e  # Exit on error

echo "🎵 RateMate Build and Install Script"
echo "======================================"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if Xcode is installed
if ! command -v xcodebuild &> /dev/null; then
    echo -e "${RED}Error: Xcode command line tools not found.${NC}"
    echo "Please install Xcode from the App Store or run: xcode-select --install"
    exit 1
fi

echo -e "${BLUE}Step 1: Building RateMate (Release)...${NC}"

# Build the app in Release configuration
xcodebuild -project RateMate.xcodeproj \
           -scheme RateMate \
           -configuration Release \
           -derivedDataPath build \
           clean build \
           CODE_SIGN_IDENTITY="" \
           CODE_SIGNING_REQUIRED=NO \
           CODE_SIGNING_ALLOWED=NO

if [ $? -ne 0 ]; then
    echo -e "${RED}Build failed! Check the error messages above.${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Build successful!${NC}"

# Find the built app
APP_PATH="build/Build/Products/Release/RateMate.app"

if [ ! -d "$APP_PATH" ]; then
    echo -e "${RED}Error: Built app not found at $APP_PATH${NC}"
    exit 1
fi

# Check if RateMate is running and kill it
if pgrep -x "RateMate" > /dev/null; then
    echo -e "${BLUE}Stopping existing RateMate...${NC}"
    killall RateMate
    sleep 1
fi

# Remove old version if it exists
if [ -d "/Applications/RateMate.app" ]; then
    echo -e "${BLUE}Removing old version...${NC}"
    rm -rf "/Applications/RateMate.app"
fi

echo -e "${BLUE}Step 2: Installing to /Applications...${NC}"

# Copy to Applications
cp -R "$APP_PATH" "/Applications/"

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to copy to /Applications. You may need to use sudo.${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Installed to /Applications!${NC}"

# Optional: Create symbolic link in Dock
echo -e "${BLUE}Step 3: Launch RateMate?${NC}"
read -p "Would you like to launch RateMate now? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    open "/Applications/RateMate.app"
    echo -e "${GREEN}✓ RateMate launched!${NC}"
fi

echo
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ Installation complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo
echo "RateMate has been installed to /Applications"
echo "You can now:"
echo "  • Find it in your Applications folder"
echo "  • Drag it to your Dock for easy access"
echo "  • Add it to Login Items in System Settings for auto-start"
echo
echo "First time setup:"
echo "  1. Grant Full Disk Access in System Settings > Privacy & Security"
echo "  2. Allow Music control when prompted"
echo "  3. Enable Auto-switch in the app menu"
echo
echo "To rebuild and update in the future, just run:"
echo "  ./build_and_install.sh"