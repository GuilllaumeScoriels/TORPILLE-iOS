#!/bin/bash
set -e
cd "$(dirname "$0")"
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "XcodeGen n'est pas installé. Installe-le avec: brew install xcodegen"
  exit 1
fi
xcodegen generate
open TorpilleIOS.xcodeproj
