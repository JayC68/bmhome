#!/usr/bin/env bash
set -euo pipefail

cd /Users/Jon/bmhome
echo "== BMHome v0.1.0-beta.29 public beta polish =="

echo "1. npm login"
npm login
npm whoami

echo "2. Clean tarballs"
rm -f homebridge-bmhome-*.tgz

echo "3. Package metadata"
node scripts/set-beta29-package.js

echo "4. Remove legacy preconditioning tile"
python3 scripts/remove-preconditioning.py

echo "5. Write README, changelog and release notes"
python3 scripts/write-beta29-docs.py

echo "6. Install and build"
npm install
npm run build

echo "7. Validate"
node scripts/validate-beta29.js

echo "8. Package dry run"
npm pack --dry-run

echo "9. Commit"
git add package.json package-lock.json README.md CHANGELOG.md .homebridge/release-notes.md src/vehicleAccessory.ts scripts/
git add -u package.json package-lock.json README.md CHANGELOG.md .homebridge/release-notes.md src/vehicleAccessory.ts scripts/

if git diff --cached --quiet; then
  echo "No staged release changes; stopping."
  exit 1
fi

git commit -m "Polish public beta HomeKit surface and documentation"

echo "10. Push to GitHub first"
git push -u origin "$(git branch --show-current)"

echo "11. Publish to npm"
npm publish

echo "12. Verify npm"
npm view homebridge-bmhome@0.1.0-beta.29 version description
npm view homebridge-bmhome@0.1.0-beta.29 engines --json

echo "== BMHome beta.29 complete =="
