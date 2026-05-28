#!/usr/bin/env bash
set -euo pipefail

REPO="/Users/Jon/bmhome"
VERSION="0.1.0-beta.13"
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"

cd "$REPO"

echo "== Install BMHome beta.13 files =="

echo "1. Copy source files"
cp "$SOURCE_DIR/src/bmwClient.ts" "$REPO/src/bmwClient.ts"
cp "$SOURCE_DIR/src/types.ts" "$REPO/src/types.ts"

echo "2. Set package metadata"
node <<'NODE'
const fs = require('fs');
const p = 'package.json';
const pkg = JSON.parse(fs.readFileSync(p, 'utf8'));
pkg.version = '0.1.0-beta.13';
pkg.repository = { type: 'git', url: 'git+https://github.com/JayC68/bmhome.git' };
pkg.bugs = { url: 'https://github.com/JayC68/bmhome/issues' };
pkg.homepage = 'https://bmhome.kernowekconsulting.co.uk';
fs.writeFileSync(p, JSON.stringify(pkg, null, 2) + '\n');
console.log(pkg.name + '@' + pkg.version);
NODE

echo "3. Build"
npm install
npm run build

echo "4. Validate"
node <<'NODE'
const fs = require('fs');
const bmw = fs.readFileSync('src/bmwClient.ts', 'utf8');
const types = fs.readFileSync('src/types.ts', 'utf8');
function fail(msg) { console.error('FAIL: ' + msg); process.exit(1); }
if (!bmw.includes('private descriptorState')) fail('descriptorState missing');
if (!bmw.includes('updateVehicleStateFromDescriptors')) fail('payload mapper missing');
if (!bmw.includes('vehicle.drivetrain.electricEngine.kombiRemainingElectricRange')) fail('range descriptor missing');
if (!bmw.includes('vehicle.cabin.door.row1.driver.isOpen')) fail('door descriptor missing');
if (!bmw.includes('vehicle.cabin.window.row1.driver.status')) fail('window descriptor missing');
if (!bmw.includes('vehicle.chassis.axle.row1.wheel.left.tire.pressure')) fail('tyre descriptor missing');
if (!bmw.includes('password: this.tokenStore.idToken')) fail('idToken MQTT password missing');
if (!bmw.includes('${this.tokenStore.gcid}/${this.config.vin')) fail('BMW documented topic missing');
if (!types.includes('doorsOpen?: boolean')) fail('VehicleData doorsOpen missing');
console.log('Validation OK');
NODE

echo "5. Package dry run"
npm pack --dry-run

echo "6. Commit"
git add package.json package-lock.json src/bmwClient.ts src/types.ts
git add -u package.json package-lock.json src/bmwClient.ts src/types.ts

if git diff --cached --quiet; then
  echo "No staged release changes; stopping."
  exit 1
fi

git commit -m "Map BMW CarData MQTT descriptor payloads"

echo "7. Push to GitHub first"
git push -u origin "$(git branch --show-current)"

echo "8. npm login and publish"
npm login
npm whoami
npm publish

echo "9. Verify"
npm view homebridge-bmhome@0.1.0-beta.13 version description || true

echo "== BMHome beta.13 file install complete =="
