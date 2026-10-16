#!/bin/bash
# 初始化开发环境：检查 XcodeGen，用 project.yml 生成 .xcodeproj。
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "没找到 xcodegen，先装一下：brew install xcodegen"
  exit 1
fi

xcodegen generate
echo "OK：已从 project.yml 生成 LifeOS.xcodeproj"
echo "用 Xcode 打开，或跑："
echo "  xcodebuild -project LifeOS.xcodeproj -scheme LifeOS -configuration Debug build"
