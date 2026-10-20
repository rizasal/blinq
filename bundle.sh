#!/bin/sh
# Builds Blinq.app (needed for notifications) and launches it
set -e
swift build -c release
APP=Blinq.app; rm -rf $APP; mkdir -p $APP/Contents/MacOS
cp .build/release/Blinq $APP/Contents/MacOS/
cat > $APP/Contents/Info.plist <<P
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.blinq.app</string>
<key>CFBundleName</key><string>Blinq</string>
<key>CFBundleExecutable</key><string>Blinq</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
P
codesign -s - --force $APP
open $APP
