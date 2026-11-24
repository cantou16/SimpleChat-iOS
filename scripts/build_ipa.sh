#!/usr/bin/env bash
# 本地出未签名 IPA（macOS / 黑苹果，需 Xcode + xcodegen）。
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null; then
  echo "缺少 xcodegen：brew install xcodegen" >&2
  exit 1
fi

xcodegen generate
rm -rf build-device Payload SimpleChatPlus-unsigned.ipa

xcodebuild -project SimpleChat.xcodeproj -scheme SimpleChat \
  -destination 'generic/platform=iOS' -configuration Release \
  -derivedDataPath build-device build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" -quiet

APP=$(find build-device/Build/Products -name "SimpleChat.app" -path "*iphoneos*" | head -1)
[ -n "$APP" ] || { echo "没有找到 device .app" >&2; exit 1; }

mkdir -p Payload
cp -R "$APP" Payload/
zip -qry SimpleChatPlus-unsigned.ipa Payload
ls -la SimpleChatPlus-unsigned.ipa
