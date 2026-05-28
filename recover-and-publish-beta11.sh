set -euo pipefail

REPO="/Users/Jon/bmhome"
VERSION="0.1.0-beta.11"

cd "$REPO"

echo "== BMHome recover and publish ${VERSION} =="

echo "1. npm login"
npm login
npm whoami

echo "2. Clean local generated clutter from failed attempts"
rm -f homebridge-bmhome-*.tgz
rm -f build-beta10.sh build-beta11.sh build-beta9.sh build-beta8-mqtt-diagnostics.sh build-beta7-auth-diagnostics.sh build-beta6-listening-mvp.sh
rm -f clean-package-publish.sh fix-build-publish.sh fix-platform-config-publish.sh git-first-publish-beta6.sh push-and-publish-https.sh set-display-name-publish.sh

echo "3. Set package metadata"
node <<'NODE'
const fs = require('fs');

const p = 'package.json';
const pkg = JSON.parse(fs.readFileSync(p, 'utf8'));

pkg.version = '0.1.0-beta.11';
pkg.repository = {
  type: 'git',
  url: 'git+https://github.com/JayC68/bmhome.git'
};
pkg.bugs = {
  url: 'https://github.com/JayC68/bmhome/issues'
};
pkg.homepage = 'https://bmhome.kernowekconsulting.co.uk';

fs.writeFileSync(p, JSON.stringify(pkg, null, 2) + '\n');
console.log(pkg.name + '@' + pkg.version);
NODE

echo "4. Patch src/bmwClient.ts to use accessToken for MQTT"
node <<'NODE'
const fs = require('fs');

const p = 'src/bmwClient.ts';
let s = fs.readFileSync(p, 'utf8');

s = s.replaceAll(
  'password: this.tokenStore.idToken,',
  'password: this.tokenStore.accessToken || this.tokenStore.idToken,'
);

s = s.replaceAll(
  'password: this.tokenStore?.idToken,',
  'password: this.tokenStore?.accessToken || this.tokenStore?.idToken,'
);

if (!s.includes('MQTT password source')) {
  const marker = 'console.log(`[BMWClient] VIN topic (BMW portal topic): ${vinTopic}`);';
  s = s.replace(
    marker,
    marker + '\n    console.log(`[BMWClient] MQTT password source: ${this.tokenStore.accessToken ? \'accessToken\' : \'idToken fallback\'}`);'
  );
}

fs.writeFileSync(p, s);
NODE

echo "5. Patch src/vehicleAccessory.ts HomeKit command snap-back only"
node <<'NODE'
const fs = require('fs');

const p = 'src/vehicleAccessory.ts';
let s = fs.readFileSync(p, 'utf8');

s = s.replace(
`      const current = this.lockService.getCharacteristic(Characteristic.LockCurrentState).value;
      if (current !== null && current !== undefined) {
        this.lockService.updateCharacteristic(Characteristic.LockTargetState, current);
      }
`,
''
);

s = s.replace(
`      this.heaterService.updateCharacteristic(Characteristic.Active, Characteristic.Active.INACTIVE);
`,
''
);

fs.writeFileSync(p, s);
NODE

echo "6. Install and build"
npm install
npm run build

echo "7. Validate intended changes"
node <<'NODE'
const fs = require('fs');

const bmw = fs.readFileSync('src/bmwClient.ts', 'utf8');
const acc = fs.readFileSync('src/vehicleAccessory.ts', 'utf8');

function fail(msg) {
  console.error('FAIL: ' + msg);
  process.exit(1);
}

if (bmw.includes('password: this.tokenStore.idToken,')) {
  fail('idToken-only MQTT password remains');
}

if (bmw.includes('password: this.tokenStore?.idToken,')) {
  fail('optional idToken-only MQTT password remains');
}

if (!bmw.includes('accessToken || this.tokenStore.idToken') && !bmw.includes('accessToken || this.tokenStore?.idToken')) {
  fail('accessToken MQTT password fallback not found');
}

if (bmw.includes('wildcardTopic') || bmw.includes('Wildcard diagnostic topic')) {
  fail('wildcard MQTT code remains');
}

if (acc.includes('LockTargetState, current')) {
  fail('lock target snap-back remains');
}

if (acc.includes('this.heaterService.updateCharacteristic(Characteristic.Active, Characteristic.Active.INACTIVE);')) {
  fail('heater immediate inactive reset remains');
}

console.log('Validation OK');
NODE

echo "8. Package dry run"
npm pack --dry-run

echo "9. Commit only tracked release files"
git add package.json package-lock.json src/bmwClient.ts src/vehicleAccessory.ts config.schema.json
git add -u package.json package-lock.json src/bmwClient.ts src/vehicleAccessory.ts config.schema.json

if git diff --cached --quiet; then
  echo "No changes staged; stopping before publish."
  exit 1
fi

git commit -m "Use MQTT access token and preserve HomeKit target states"

echo "10. Push to GitHub first"
git push -u origin "$(git branch --show-current)"

echo "11. Publish to npm"
npm publish

echo "12. Verify deployment"
git status --short
git log --oneline -3
npm view homebridge-bmhome@0.1.0-beta.11 version description

echo "== BMHome beta.11 published =="
