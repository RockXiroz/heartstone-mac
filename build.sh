#!/bin/bash
# Build script for HearthstoneBGHelper on macOS
# Requirements: Xcode 15+, macOS 13+
set -e

SCHEME="HearthstoneBGHelper"
BUILD_DIR=".build/release"

echo "🔨 Building $SCHEME..."
swift build -c release 2>&1

echo ""
echo "✅ Build successful!"
echo ""
echo "Binary location: $BUILD_DIR/$SCHEME"
echo ""
echo "To run:"
echo "  ./$BUILD_DIR/$SCHEME"
echo ""
echo "NOTE: On first launch, macOS will prompt for Screen Recording permission."
echo "      Go to System Settings → Privacy & Security → Screen Recording → Enable HearthstoneBGHelper"
