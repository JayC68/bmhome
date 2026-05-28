set -euo pipefail
cd /Users/Jon/bmhome

echo "== BMHome v0.1.0-beta.26 fix cached HomeKit service restore =="

npm login
npm whoami
rm -f homebridge-bmhome-*.tgz

node - <<'NODE'
const fs = require('fs');
const p = 'package.json';
const pkg = JSON.parse(fs.readFileSync(p, 'utf8'));
pkg.version = '0.1.0-beta.26';
fs.writeFileSync(p, JSON.stringify(pkg, null, 2) + '\n');
NODE

python3 <<'PY'
from pathlib import Path
p = Path("src/vehicleAccessory.ts")
s = p.read_text()

s = s.replace(
"""    this.doorsService =
      accessory.getService('Doors') ??
      accessory.addService(api.hap.Service.ContactSensor, `${name} Doors`, 'doors');

    this.windowsService =
      accessory.getService('Windows') ??
      accessory.addService(api.hap.Service.ContactSensor, `${name} Windows`, 'windows');

    this.bootService =
      accessory.getService('Boot') ??
      accessory.addService(api.hap.Service.ContactSensor, `${name} Boot`, 'boot');

    this.tyresService =
      accessory.getService('Tyres OK') ??
      accessory.addService(api.hap.Service.Switch, `${name} Tyres OK`, 'tyres');""",
"""    this.doorsService =
      accessory.getServiceById(api.hap.Service.ContactSensor, 'doors') ??
      accessory.addService(api.hap.Service.ContactSensor, `${name} Doors`, 'doors');

    this.windowsService =
      accessory.getServiceById(api.hap.Service.ContactSensor, 'windows') ??
      accessory.addService(api.hap.Service.ContactSensor, `${name} Windows`, 'windows');

    this.bootService =
      accessory.getServiceById(api.hap.Service.ContactSensor, 'boot') ??
      accessory.addService(api.hap.Service.ContactSensor, `${name} Boot`, 'boot');

    this.tyresService =
      accessory.getServiceById(api.hap.Service.Switch, 'tyres') ??
      accessory.addService(api.hap.Service.Switch, `${name} Tyres OK`, 'tyres');"""
)

p.write_text(s)
PY

npm install
npm run build

node - <<'NODE'
const fs = require('fs');
const s = fs.readFileSync('dist/vehicleAccessory.js', 'utf8');
if (!s.includes('getServiceById')) throw new Error('getServiceById fix missing');
console.log('Validation OK');
NODE

npm pack --dry-run

git add package.json package-lock.json src/vehicleAccessory.ts
git add -u package.json package-lock.json src/vehicleAccessory.ts
git commit -m "Fix cached HomeKit service restore"
git push -u origin "$(git branch --show-current)"
npm publish
npm view homebridge-bmhome@0.1.0-beta.26 version description

echo "== BMHome beta.26 complete =="
