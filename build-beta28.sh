set -euo pipefail
cd /Users/Jon/bmhome

echo "== BMHome v0.1.0-beta.28 simplify HomeKit tiles =="

npm login
npm whoami
rm -f homebridge-bmhome-*.tgz

node - <<'NODE'
const fs = require('fs');
const p = 'package.json';
const pkg = JSON.parse(fs.readFileSync(p, 'utf8'));
pkg.version = '0.1.0-beta.28';
fs.writeFileSync(p, JSON.stringify(pkg, null, 2) + '\n');
NODE

python3 <<'PY'
from pathlib import Path
p = Path("src/vehicleAccessory.ts")
s = p.read_text()

s = s.replace("  private doorsService!: Service;\n", "")

start = """    this.doorsService =
      accessory.getServiceById(api.hap.Service.ContactSensor, 'doors') ??
      accessory.addService(api.hap.Service.ContactSensor, 'BMW Doors', 'doors');

"""
s = s.replace(start, "")

s = s.replace("    this.setServiceName(this.doorsService, 'BMW Doors');\n", "")

s = s.replace("    this.updateContact(this.doorsService, data.doorsOpen);\n", "")

p.write_text(s)
PY

npm install
npm run build

node - <<'NODE'
const fs = require('fs');
const s = fs.readFileSync('dist/vehicleAccessory.js', 'utf8');

for (const term of [
  'BMW Lock',
  'BMW Battery',
  'BMW Windows',
  'BMW Boot',
  'BMW Tyres',
  'BMW Preconditioning',
  'getServiceById'
]) {
  if (!s.includes(term)) throw new Error(term + ' missing');
}

if (s.includes('BMW Doors')) throw new Error('BMW Doors tile still present');

console.log('Validation OK');
NODE

npm pack --dry-run

git add package.json package-lock.json src/vehicleAccessory.ts
git add -u package.json package-lock.json src/vehicleAccessory.ts

git commit -m "Simplify HomeKit tiles by removing doors sensor"
git push -u origin "$(git branch --show-current)"

npm publish
npm view homebridge-bmhome@0.1.0-beta.28 version description

echo "== BMHome beta.28 complete =="
