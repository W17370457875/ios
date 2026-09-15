#!/usr/bin/env bash
# 在 macOS 上把 WebShell 打包成 IPA。
#
# 用法:
#   bash scripts/build.sh                                       # 未签名 / Ad-hoc IPA
#   CODE_SIGN_IDENTITY="..." PROFILE=app.mobileprovision \
#     bash scripts/build.sh                                     # 用开发者证书签名
#
# 环境变量:
#   APP_NAME / BUNDLE_ID / VERSION / BUILD_NO / MIN_IOS
#   HOME_URL        （覆盖源码里的首页地址，留空则用默认）
#   CODE_SIGN_IDENTITY   ("-" = ad-hoc 自签名，空则默认 ad-hoc)
#   PROFILE              （.mobileprovision 文件路径，可选）
set -euo pipefail

APP_NAME="${APP_NAME:-WebShell}"
BUNDLE_ID="${BUNDLE_ID:-com.example.webshell}"
VERSION="${VERSION:-1.0}"
BUILD_NO="${BUILD_NO:-1}"
MIN_IOS="${MIN_IOS:-15.0}"
HOME_URL="${HOME_URL:-}"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
PROFILE="${PROFILE:-}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC="$ROOT/Sources"
RES="$ROOT/Resources"
BUILD="$ROOT/build"
APP="$BUILD/Payload/$APP_NAME.app"
PLB=/usr/libexec/PlistBuddy

echo "==> 准备构建目录"
rm -rf "$BUILD"
mkdir -p "$APP"

echo "==> 编译 Swift 源码 (arm64-apple-ios$MIN_IOS)"
SDK_PATH="$(xcrun --sdk iphoneos --show-sdk-path)"
SRC_COPY="$BUILD/Sources"
mkdir -p "$SRC_COPY"
cp "$SRC"/*.swift "$SRC_COPY"/

if [[ -n "$HOME_URL" ]]; then
  HOME_URL="$HOME_URL" perl -pi -e 's{^(\s*private let kHomeURL = ).*}{$1"$ENV{HOME_URL}";}g' "$SRC_COPY/WebViewController.swift"
fi

xcrun --sdk iphoneos swiftc \
  -target "arm64-apple-ios$MIN_IOS" \
  -sdk "$SDK_PATH" \
  -parse-as-library \
  -O -whole-module-optimization \
  -o "$APP/$APP_NAME" \
  "$SRC_COPY/AppDelegate.swift" \
  "$SRC_COPY/WebViewController.swift"

echo "==> 写入 Info.plist"
cp "$RES/Info.plist" "$APP/Info.plist"
"$PLB" -c "Set :CFBundleName $APP_NAME" "$APP/Info.plist"
"$PLB" -c "Set :CFBundleDisplayName $APP_NAME" "$APP/Info.plist"
"$PLB" -c "Set :CFBundleExecutable $APP_NAME" "$APP/Info.plist"
"$PLB" -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Info.plist"
"$PLB" -c "Set :CFBundleShortVersionString $VERSION" "$APP/Info.plist"
"$PLB" -c "Set :CFBundleVersion $BUILD_NO" "$APP/Info.plist"
"$PLB" -c "Set :MinimumOSVersion $MIN_IOS" "$APP/Info.plist"

echo "==> 编译资源（图标 / 启动图）"
if xcrun actool "$RES/Assets.xcassets" --compile "$APP" \
    --platform iphoneos --minimum-deployment-target "$MIN_IOS" \
    --app-icon AppIcon --output-partial-info-plist "$BUILD/partial.plist" 2>/dev/null; then
  echo "    图标已编译 (Assets.car)"
else
  echo "    警告: actool 失败，将不含应用图标"
fi

if xcrun ibtool --compile "$APP/LaunchScreen.storyboardc" "$RES/LaunchScreen.storyboard" 2>/dev/null; then
  "$PLB" -c "Add :UILaunchStoryboardName string LaunchScreen" "$APP/Info.plist" 2>/dev/null || \
  "$PLB" -c "Set :UILaunchStoryboardName LaunchScreen" "$APP/Info.plist"
  echo "    启动图已编译"
else
  "$PLB" -c "Add :UILaunchScreen dict" "$APP/Info.plist" 2>/dev/null || true
  echo "    警告: ibtool 失败，使用纯色启动图"
fi

echo "==> 签名"
if [[ -n "$PROFILE" && -f "$PROFILE" ]]; then
  cp "$PROFILE" "$APP/embedded.mobileprovision"
fi
if [[ "$CODE_SIGN_IDENTITY" == "-" ]]; then
  codesign --force --sign - --entitlements "$RES/Entitlements.plist" --timestamp=none "$APP"
else
  codesign --force --sign "$CODE_SIGN_IDENTITY" --entitlements "$RES/Entitlements.plist" --timestamp=none "$APP"
fi

echo "==> 打包 IPA"
( cd "$BUILD" && zip -qry "$APP_NAME.ipa" Payload )
echo "==> 完成: $BUILD/$APP_NAME.ipa"
