#!/usr/bin/env bash
set -euo pipefail

echo "== BMHome v0.1.0-beta.30 telemetry-only polish =="

npm login

mkdir -p scripts

cat > scripts/set-beta30-package.js <<'NODE'
const fs = require('fs');

const pkgPath = './package.json';
const pkg = JSON.parse(fs.readFileSync(pkgPath, 'utf8'));

pkg.version = '0.1.0-beta.30';

pkg.description =
  'BMW CarData telemetry for Apple Home via Homebridge';

pkg.displayName = 'BM Home';

pkg.keywords = [
  'homebridge-plugin',
  'bmw',
  'mini',
  'cardata',
  'mqtt',
  'apple-home',
  'homekit',
  'telemetry',
  'ev'
];

fs.writeFileSync(pkgPath, JSON.stringify(pkg, null, 2) + '\n');

console.log('Updated package.json -> 0.1.0-beta.30');
NODE

/opt/homebrew/bin/node scripts/set-beta30-package.js || node scripts/set-beta30-package.js

echo
echo "== Removing Lock accessory/service =="

perl -0pi -e 's~\n\s*this\.lockService[\s\S]*?this\.services\.push\(this\.lockService\);\n~~g' src/vehicleAccessory.ts

perl -0pi -e 's~\n\s*private lockService:[^;]*;~~g' src/vehicleAccessory.ts

perl -0pi -e 's~\n\s*this\.updateLockState\(\);~~g' src/vehicleAccessory.ts

perl -0pi -e 's~\n\s*private updateLockState\([\s\S]*?\n\s*}\n~~g' src/vehicleAccessory.ts

echo
echo "== Removing remote-control wording from README =="

perl -0pi -e 's/remote control/telemetry/g' README.md
perl -0pi -e 's/lock\/unlock[^.,;\n]*//gi' README.md
perl -0pi -e 's/remote commands[^.,;\n]*//gi' README.md
perl -0pi -e 's/vehicle control[^.,;\n]*//gi' README.md

cat >> README.md <<'README'

---

## BMW CarData Limitations

BMHome uses BMW CarData Stream, which is currently a telemetry-focused platform.

BMW presently restricts most third-party command and remote-control functionality, including vehicle lock/unlock operations.

Because BMHome only exposes data BMW publishes through CarData Stream:

- some values may be delayed
- some values may disappear temporarily
- some descriptors may not exist for all vehicles
- updates may pause while the vehicle sleeps
- telemetry availability varies by region, firmware and vehicle model

Current BMHome focus areas:

- EV range visibility
- battery telemetry (when available)
- window-open awareness
- boot/tailgate state
- tyre status visibility
- lightweight Apple Home presence

BMHome does not attempt to bypass BMW platform restrictions.

README

echo
echo "== Updating CHANGELOG =="

cat > CHANGELOG.md <<'CHANGELOG'
# Changelog

## v0.1.0-beta.30

### Changed

- Repositioned BMHome as a telemetry-focused BMW CarData integration
- Removed Lock accessory/tile
- Removed remote-control wording and semantics
- Simplified Apple Home presentation
- Improved README transparency around BMW CarData limitations
- Clarified telemetry variability and vehicle sleep behaviour

### Notes

BMW currently limits third-party integrations primarily to telemetry data exposed through BMW CarData Stream.

BMHome intentionally focuses on stable Apple Home telemetry surfaces rather than unsupported remote-control features.

CHANGELOG

echo
echo "== Build =="

npm install
npm run build

echo
echo "== Sanity check =="

grep -R "BMW Lock" dist src || true
grep -R "lockService" dist src || true
grep -R "remote control" README.md || true

echo
echo "== Git =="

git add .
git commit -m "Telemetry-only repositioning for beta.30"

git push -u origin "$(git branch --show-current)"

echo
echo "== Publish =="

npm publish --tag beta

echo
echo "== Done =="
echo "Published: homebridge-bmhome@0.1.0-beta.30"

