#!/usr/bin/env bash
set -euo pipefail

cd /Users/Jon/bmhome
echo "== BM Home Stream v0.1.0-beta.31 clean telemetry build =="

npm login
npm whoami
rm -f homebridge-bmhome-*.tgz

python3 scripts/write-beta31-files.py

rm -rf dist
npm install
npm run build

node scripts/validate-beta31.js

npm pack --dry-run

git add package.json package-lock.json README.md CHANGELOG.md .homebridge/release-notes.md src/vehicleAccessory.ts scripts/write-beta31-files.py scripts/validate-beta31.js
git add -u package.json package-lock.json README.md CHANGELOG.md .homebridge/release-notes.md src/vehicleAccessory.ts

if git diff --cached --quiet; then
  echo "No staged release changes; stopping."
  exit 1
fi

git commit -m "Rename to BM Home Stream and remove lock semantics"
git push -u origin "$(git branch --show-current)"
npm publish --tag beta

npm view homebridge-bmhome@0.1.0-beta.31 version displayName description
echo "== BM Home Stream beta.31 complete =="
