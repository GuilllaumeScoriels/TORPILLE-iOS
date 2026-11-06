#!/bin/bash
# Vérification Torpille préparée par Claude : compilation + tests iOS, tests Cloud Functions,
# tests des règles Firestore sur un émulateur LOCAL (aucun accès à la production, aucun déploiement).
cd "$(dirname "$0")/.." || exit 1
OUT=build/claude-verify
mkdir -p "$OUT"; rm -rf "$OUT/TorpilleTests.xcresult"
exec > >(tee "$OUT/run.log") 2>&1
echo "== Démarrage $(date)"

echo "== 1/3 Compilation et tests iOS (simulateur)"
SIM=$(xcrun simctl list devices available | grep -E "^ +iPhone [0-9]+ Pro \(" | head -1 | sed -E 's/^ +(iPhone [0-9]+ Pro) \(.*/\1/')
[ -z "$SIM" ] && SIM="iPhone 17 Pro"
echo "Simulateur : $SIM"
xcodebuild test -project TorpilleIOS.xcodeproj -scheme TorpilleIOS \
  -destination "platform=iOS Simulator,name=$SIM" \
  -derivedDataPath build/ReviewDerivedData -resultBundlePath "$OUT/TorpilleTests.xcresult" \
  ENABLE_TESTABILITY=YES > "$OUT/xcodebuild.log" 2>&1
echo "xcodebuild code de sortie : $?"
grep -E "error:|warning: .*(Reaction|reaction)|Test Case .* failed|Executed [0-9]+ test|\*\* (TEST|BUILD) " "$OUT/xcodebuild.log" | tail -60

echo "== 2/3 Tests Cloud Functions"
node --test functions/*.test.js 2>&1 | grep -E "^# (tests|pass|fail)"

echo "== 3/3 Règles Firestore (émulateur local)"
DEPS="$PWD/build/claude-rules-deps"
if [ ! -d "$DEPS/node_modules/@firebase/rules-unit-testing" ]; then
  mkdir -p "$DEPS" && (cd "$DEPS" && npm init -y >/dev/null && npm i --silent @firebase/rules-unit-testing firebase)
fi
if command -v firebase >/dev/null; then FB=firebase; else FB="npx --yes firebase-tools"; fi
$FB emulators:exec --only firestore --project demo-torpille-reactions \
  "RULE_TEST_PACKAGE=$DEPS/package.json node tools/reaction-rules-test.cjs" 2>&1 | grep -vE "^i  |^\s*$" | tail -25

echo "== Terminé $(date). Tu peux fermer cette fenêtre."
