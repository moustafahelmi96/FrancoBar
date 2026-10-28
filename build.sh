#!/bin/zsh
# ./build.sh            build FrancoBar.app here
# ./build.sh install    build, copy to /Applications and relaunch
# ./build.sh release    universal (Apple silicon + Intel) build zipped as FrancoBar.zip
set -e
cd "$(dirname "$0")"
APP=FrancoBar.app
rm -rf $APP && mkdir -p $APP/Contents/MacOS
BIN=$APP/Contents/MacOS/FrancoBar
if [[ "$1" == release ]]; then
  for arch in arm64 x86_64; do
    swiftc -O -swift-version 5 -target $arch-apple-macos13 *.swift -o $BIN-$arch
  done
  lipo -create $BIN-arm64 $BIN-x86_64 -output $BIN
  rm $BIN-arm64 $BIN-x86_64
else
  swiftc -O -swift-version 5 -target "$(uname -m)-apple-macos13" *.swift -o $BIN
fi
# App icon: icon/AppIcon.png (drawn by icon/make-icon.swift) → AppIcon.icns
ICONSET=$(mktemp -d)/AppIcon.iconset
mkdir -p $ICONSET $APP/Contents/Resources
for s in 16 32 128 256 512; do
  sips -z $s $s icon/AppIcon.png --out $ICONSET/icon_${s}x${s}.png >/dev/null
  sips -z $((s * 2)) $((s * 2)) icon/AppIcon.png --out $ICONSET/icon_${s}x${s}@2x.png >/dev/null
done
iconutil -c icns $ICONSET -o $APP/Contents/Resources/AppIcon.icns
rm -rf $(dirname $ICONSET)
cat > $APP/Contents/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>FrancoBar</string>
<key>CFBundleIdentifier</key><string>com.moustafahelmi96.francobar</string>
<key>CFBundleExecutable</key><string>FrancoBar</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>2.1</string>
<key>CFBundleVersion</key><string>3</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force -s - $APP
echo "Built $PWD/$APP"
if [[ "$1" == release ]]; then
  rm -f FrancoBar.zip
  ditto -c -k --keepParent $APP FrancoBar.zip
  echo "Zipped $PWD/FrancoBar.zip"
fi
if [[ "$1" == install ]]; then
  pkill -x FrancoBar || true
  while pgrep -x FrancoBar >/dev/null; do sleep 0.1; done
  rm -rf /Applications/$APP
  cp -R $APP /Applications/
  open /Applications/$APP 2>/dev/null || { sleep 1; open /Applications/$APP; }
  echo "Installed to /Applications and launched"
fi
