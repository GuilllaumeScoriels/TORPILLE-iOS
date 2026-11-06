#!/bin/bash
# Torpille — vérification puis déploiement ciblé, préparé par Claude.
#  1. Compilation + tests iOS (simulateur)            -> informatif
#  2. Tests des Cloud Functions                        -> bloquant
#  3. Tests des règles Firestore sur émulateur LOCAL   -> bloquant
#  4. Déploiement CIBLÉ (jamais "--only functions" seul, qui supprimerait
#     5 fonctions de production absentes du code local).
cd "$(dirname "$0")/.." || exit 1
PROJECT=torpille-38783
FUNCS="applyExpiredTorpillePenalty updateCommunitySettings notifyOnCommunitySettingsChanged getContactDiscoverySettings setContactDiscoverySettings findPhoneContacts createVideoTorpille"
OUT=build/claude-verify
mkdir -p "$OUT"; rm -rf "$OUT/TorpilleTests.xcresult"
exec > >(tee "$OUT/run.log") 2>&1
echo "== Démarrage $(date)"

echo "== 1/4 Compilation et tests iOS"
SIM=$(xcrun simctl list devices available | grep -E "^ +iPhone [0-9]+ Pro \(" | head -1 | sed -E 's/^ +(iPhone [0-9]+ Pro) \(.*/\1/')
[ -z "$SIM" ] && SIM="iPhone 17 Pro"
echo "Simulateur : $SIM"
xcodebuild test -project TorpilleIOS.xcodeproj -scheme TorpilleIOS \
  -destination "platform=iOS Simulator,name=$SIM" \
  -derivedDataPath build/ReviewDerivedData -resultBundlePath "$OUT/TorpilleTests.xcresult" \
  ENABLE_TESTABILITY=YES > "$OUT/xcodebuild.log" 2>&1
echo "IOS_EXIT=$?"
grep -E "error:|Test Case .* failed|Executed [0-9]+ test|\*\* (TEST|BUILD) " "$OUT/xcodebuild.log" | tail -60

echo "== 2/4 Tests Cloud Functions"
node --test functions/*.test.js > "$OUT/functions-tests.log" 2>&1; FN_EXIT=$?
grep -E "^# (tests|pass|fail)|not ok" "$OUT/functions-tests.log"; echo "FUNCTIONS_EXIT=$FN_EXIT"

echo "== 3/4 Règles Firestore (émulateur local)"
DEPS="$PWD/build/claude-rules-deps"
if [ ! -d "$DEPS/node_modules/@firebase/rules-unit-testing" ]; then
  mkdir -p "$DEPS" && (cd "$DEPS" && npm init -y >/dev/null && npm i --silent @firebase/rules-unit-testing firebase)
fi
if command -v firebase >/dev/null; then FB=firebase; else FB="npx --yes firebase-tools"; fi
mkdir -p build/claude-rules
sed -E "s/port: *8186/port: 8080/" tools/contact-schedule-rules-test.cjs > build/claude-rules/contact-schedule.cjs
sed -E "s/port: *8192/port: 8080/" tools/push-notification-rules-test.cjs > build/claude-rules/push.cjs
$FB emulators:exec --only firestore --project demo-torpille-rules \
  "export RULE_TEST_PACKAGE=$DEPS/package.json; node tools/reaction-rules-test.cjs && node tools/legacy-compat-rules-test.cjs && node build/claude-rules/contact-schedule.cjs && node build/claude-rules/push.cjs" \
  > "$OUT/rules-tests.log" 2>&1; RULES_EXIT=$?
grep -E "passed|PASS|Error|error|failed|FAIL" "$OUT/rules-tests.log" | grep -v "^i " | tail -30; echo "RULES_EXIT=$RULES_EXIT"

echo "== 4/4 Déploiement"
if [ "$FN_EXIT" != 0 ] || [ "$RULES_EXIT" != 0 ]; then
  echo "DEPLOY=SKIPPED (tests serveur ou règles en échec)"; echo "== Terminé $(date)"; exit 1
fi
if ! $FB login:list 2>/dev/null | grep -q "@"; then
  echo "DEPLOY=SKIPPED (Firebase CLI non connecté : lance 'firebase login' puis relance ce script)"; exit 1
fi
ONLY="firestore:rules"; for f in $FUNCS; do ONLY="$ONLY,functions:$f"; done
echo "Cible : $ONLY"
$FB deploy --only "$ONLY" --project $PROJECT --non-interactive > "$OUT/deploy.log" 2>&1; DEPLOY_EXIT=$?
tail -40 "$OUT/deploy.log"; echo "DEPLOY_EXIT=$DEPLOY_EXIT"
$FB functions:list --project $PROJECT > "$OUT/functions-list.txt" 2>&1
echo "== Terminé $(date). Tu peux fermer cette fenêtre."
