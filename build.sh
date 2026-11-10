#!/bin/zsh
set -e
cd "$(dirname "$0")"
APP=Enchufe.app
rm -rf $APP && mkdir -p $APP/Contents/MacOS
swiftc -O main.swift -o $APP/Contents/MacOS/Enchufe -framework IOKit -framework ServiceManagement
cat > $APP/Contents/Info.plist <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Enchufe</string>
<key>CFBundleIdentifier</key><string>io.alan.enchufe</string>
<key>CFBundleExecutable</key><string>Enchufe</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>13.0</string>
</dict></plist>
P
codesign --force -s - $APP
echo "listo: $PWD/$APP"
