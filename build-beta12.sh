set -euo pipefail

REPO="/Users/Jon/bmhome"
VERSION="0.1.0-beta.12"

cd "$REPO"

echo "== BMHome ${VERSION} BMW-doc MQTT alignment =="

echo "1. npm login"
npm login
npm whoami

echo "2. Clean tarballs"
rm -f homebridge-bmhome-*.tgz

echo "3. Set package metadata"
node <<'NODE'
const fs = require('fs');
const p = 'package.json';
const pkg = JSON.parse(fs.readFileSync(p, 'utf8'));

pkg.version = '0.1.0-beta.12';
pkg.repository = { type: 'git', url: 'git+https://github.com/JayC68/bmhome.git' };
pkg.bugs = { url: 'https://github.com/JayC68/bmhome/issues' };
pkg.homepage = 'https://bmhome.kernowekconsulting.co.uk';

fs.writeFileSync(p, JSON.stringify(pkg, null, 2) + '\n');
console.log(pkg.name + '@' + pkg.version);
NODE

echo "4. Patch src/bmwClient.ts"
node <<'NODE'
const fs = require('fs');
const p = 'src/bmwClient.ts';
let s = fs.readFileSync(p, 'utf8');

// BMW docs: MQTT username = GCID, password = current ID token.
s = s.replaceAll(
  'password: this.tokenStore.accessToken || this.tokenStore.idToken,',
  'password: this.tokenStore.idToken,'
);
s = s.replaceAll(
  'password: this.tokenStore?.accessToken || this.tokenStore?.idToken,',
  'password: this.tokenStore?.idToken,'
);

// BMW docs: subscribe to username/topic, not bare VIN.
s = s.replaceAll(
  'const vinTopic = this.config.vin || \'+\';',
  'const vinTopic = `${this.tokenStore.gcid}/${this.config.vin || \'+\'}`;'
);

// Clear old misleading log text.
s = s.replaceAll(
  'console.log(`[BMWClient] VIN topic (BMW portal topic): ${vinTopic}`);',
  'console.log(`[BMWClient] MQTT subscribe topic (BMW docs username/topic): ${vinTopic}`);'
);
s = s.replaceAll(
  "console.log(`[BMWClient] MQTT password source: ${this.tokenStore.accessToken ? 'accessToken' : 'idToken fallback'}`);",
  "console.log('[BMWClient] MQTT password source: idToken');"
);
s = s.replaceAll(
  'console.log(`[BMWClient] Subscribing to BMW portal topic: ${topic}`);',
  'console.log(`[BMWClient] Subscribing to BMW documented topic: ${topic}`);'
);

// Add ID token safe diagnostics.
if (!s.includes('decodeJwtPayload')) {
  s = s.replace(
    'export class BMWClient {',
`function decodeJwtPayload(token?: string): any {
  try {
    if (!token) {
      return null;
    }

    const part = token.split('.')[1];
    if (!part) {
      return null;
    }

    const normalized = part.replace(/-/g, '+').replace(/_/g, '/');
    const padded = normalized.padEnd(normalized.length + ((4 - normalized.length % 4) % 4), '=');
    return JSON.parse(Buffer.from(padded, 'base64').toString('utf8'));
  } catch {
    return null;
  }
}

export class BMWClient {`
  );
}

if (!s.includes('BMW ID token decoded diagnostics')) {
  s = s.replace(
    "console.log('[BMWClient] MQTT password source: idToken');",
`console.log('[BMWClient] MQTT password source: idToken');

    const idTokenPayload = decodeJwtPayload(this.tokenStore.idToken);
    if (idTokenPayload) {
      console.log('[BMWClient] BMW ID token decoded diagnostics:');
      console.log(\`[BMWClient] token aud: \${JSON.stringify(idTokenPayload.aud || null)}\`);
      console.log(\`[BMWClient] token scope: \${JSON.stringify(idTokenPayload.scope || idTokenPayload.scopes || null)}\`);
      console.log(\`[BMWClient] token dynamic scopes: \${JSON.stringify(idTokenPayload.dynamic_scopes || idTokenPayload.dynamicScopes || idTokenPayload.dyn_scopes || null)}\`);
      console.log(\`[BMWClient] token exp: \${JSON.stringify(idTokenPayload.exp || null)}\`);
    } else {
      console.log('[BMWClient] BMW ID token could not be decoded for diagnostics');
    }`
  );
}

fs.writeFileSync(p, s);
NODE

echo "5. Ensure HomeKit snap-back fixes remain"
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

echo "6. Install/build"
npm install
npm run build

echo "7. Validate"
node <<'NODE'
const fs = require('fs');
const bmw = fs.readFileSync('src/bmwClient.ts', 'utf8');
const acc = fs.readFileSync('src/vehicleAccessory.ts', 'utf8');

function fail(msg) {
  console.error('FAIL: ' + msg);
  process.exit(1);
}

if (!bmw.includes('password: this.tokenStore.idToken') && !bmw.includes('password: this.tokenStore?.idToken')) {
  fail('idToken MQTT password not found');
}
if (bmw.includes('accessToken || this.tokenStore.idToken') || bmw.includes('accessToken || this.tokenStore?.idToken')) {
  fail('accessToken MQTT password fallback still present');
}
if (!bmw.includes('${this.tokenStore.gcid}/${this.config.vin')) {
  fail('documented gcid/VIN topic not found');
}
if (!bmw.includes('BMW ID token decoded diagnostics')) {
  fail('ID token diagnostics missing');
}
if (acc.includes('LockTargetState, current')) {
  fail('lock snap-back remains');
}
if (acc.includes('this.heaterService.updateCharacteristic(Characteristic.Active, Characteristic.Active.INACTIVE);')) {
  fail('heater snap-back remains');
}

console.log('Validation OK');
NODE

echo "8. Package dry run"
npm pack --dry-run

echo "9. Commit"
git add package.json package-lock.json src/bmwClient.ts src/vehicleAccessory.ts config.schema.json
git add -u package.json package-lock.json src/bmwClient.ts src/vehicleAccessory.ts config.schema.json

if git diff --cached --quiet; then
  echo "No staged release changes; stopping."
  exit 1
fi

git commit -m "Align MQTT auth and topic with BMW CarData docs"

echo "10. Push to GitHub first"
git push -u origin "$(git branch --show-current)"

echo "11. Publish to npm"
npm publish

echo "12. Verify"
npm view homebridge-bmhome@0.1.0-beta.12 version description

echo "== BMHome beta.12 complete =="
