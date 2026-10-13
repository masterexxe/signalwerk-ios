#!/bin/bash
# Ergebnisse des Laufs in den Zweig ci-results schieben. Immer nur der neueste Lauf, damit das
# Repo klein bleibt; mit APPEND=1 kommen Dateien zum vorhandenen Stand dazu (TestFlight-Job).
# Braucht contents: write für GITHUB_TOKEN.
set -euo pipefail
# Absoluter Pfad: Das Skript wechselt gleich in ein eigenes Arbeitsverzeichnis.
DIR=$(cd "$1" && pwd)
BRANCH=ci-results
REMOTE="https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"
WORK=$(mktemp -d)
cd "$WORK"
git init -q
git checkout -q -b "$BRANCH"
git config user.name "Signalwerk CI"
git config user.email "ci@signalwerk.invalid"
git remote add origin "$REMOTE"
if [ "${APPEND:-0}" = 1 ] && git fetch -q --depth 1 origin "$BRANCH" 2>/dev/null; then
  git checkout -q FETCH_HEAD -- . 2>/dev/null || true
fi
cp -R "$DIR"/. "$WORK"/
cat > "$WORK/README.md" <<EOF
# Ergebnisse des letzten Cloud-Builds

- Lauf: ${GITHUB_RUN_NUMBER:-?} (${GITHUB_SHA:0:7}), $(date -u +"%Y-%m-%d %H:%M UTC")
- Ergebnis: summary.md, Bilder unter screens/, Logs als *.log
EOF
git add -A
git commit -q -m "Lauf ${GITHUB_RUN_NUMBER:-?} (${GITHUB_SHA:0:7})"
git push -q --force origin "$BRANCH"
echo "Ergebnisse in $BRANCH abgelegt."
