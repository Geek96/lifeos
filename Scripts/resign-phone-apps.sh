#!/bin/zsh
# 每周续签手机 App（免费 Apple ID 的签名 7 天过期）。
# 1. 用 AppleScript 让 Xcode 自己编一次（Xcode 界面能读到 Apple 账号，会自动续签名文件；命令行读不到）
# 2. 再用命令行编译，并用 devicectl 装到 iPhone（插线或同一 Wi-Fi 都行）
# 用法：Scripts/resign-phone-apps.sh            # 续签 LifeOS + ScanOS
#       Scripts/resign-phone-apps.sh scan-os    # 只续签某一个
set -u
DEVICE=00008130-001044441108001C
typeset -A APPS
APPS=(life-os "LifeOS.xcodeproj LifeOSPhone"  scan-os "ScanOS.xcodeproj ScanOSPhone")
targets=(${@:-${(k)APPS}})
fail=0
for repo in $targets; do
  read proj scheme <<< "${APPS[$repo]}"
  dir=~/Desktop/$repo
  echo "== $repo ($scheme)"
  (cd $dir && xcodegen generate -q) || { echo "xcodegen 失败"; fail=1; continue; }
  open -g "$dir/$proj"; sleep 5
  osascript <<OSA || { echo "Xcode 编译（续签）失败"; fail=1; continue; }
tell application "Xcode"
  set d to workspace document "$proj"
  set active scheme of d to scheme "$scheme" of d
  repeat with r in (run destinations of d)
    if (name of r) is "iPhone" then set active run destination of d to r
  end repeat
  set res to build d
  repeat 300 times
    if completed of res then exit repeat
    delay 2
  end repeat
end tell
OSA
  (cd $dir && xcodebuild -project $proj -scheme $scheme -configuration Debug -destination "id=$DEVICE" \
     -derivedDataPath build.noindex -allowProvisioningUpdates build 2>&1 | grep -E "error:|BUILD" | tail -2)
  app=$dir/build.noindex/Build/Products/Debug-iphoneos/$scheme.app
  xcrun devicectl device install app --device $DEVICE $app 2>&1 | grep -E "App installed|ERROR" | head -2 || fail=1
done
echo "== 签名文件到期时间"
for f in ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/*; do
  print -- "$(security cms -D -i "$f" 2>/dev/null | plutil -extract Entitlements.application-identifier raw - 2>/dev/null)  $(security cms -D -i "$f" 2>/dev/null | plutil -extract ExpirationDate raw - 2>/dev/null)"
done
exit $fail
