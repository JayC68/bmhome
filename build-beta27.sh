set -euo pipefail
cd /Users/Jon/bmhome

echo "== BMHome v0.1.0-beta.27 human-readable HomeKit tile names =="

npm login
npm whoami
rm -f homebridge-bmhome-*.tgz

node - <<'NODE'
const fs = require('fs');
const p = 'package.json';
const pkg = JSON.parse(fs.readFileSync(p, 'utf8'));
pkg.version = '0.1.0-beta.27';
fs.writeFileSync(p, JSON.stringify(pkg, null, 2) + '\n');
NODE

python3 <<'PY'
from pathlib import Path

p = Path("src/vehicleAccessory.ts")
s = p.read_text()

# Insert helper if missing.
if "private setServiceName" not in s:
    s = s.replace(
"""  private setupHandlers(): void {""",
"""  private setServiceName(service: Service, name: string): void {
    const { Characteristic } = this.api.hap;

    service.setCharacteristic(Characteristic.Name, name);

    try {
      service.setCharacteristic(Characteristic.ConfiguredName, name);
    } catch {
      // ConfiguredName is not available on every Homebridge/HAP version.
    }
  }

  private setupHandlers(): void {"""
    )

# Replace service creation labels with stable human names.
replacements = {
"accessory.addService(api.hap.Service.LockMechanism, `${name} Lock`, 'lock')":
"accessory.addService(api.hap.Service.LockMechanism, 'BMW Lock', 'lock')",

"accessory.addService(api.hap.Service.Battery, `${name} Battery`, 'battery')":
"accessory.addService(api.hap.Service.Battery, 'BMW Battery', 'battery')",

"accessory.addService(api.hap.Service.HeaterCooler, `${name} Preconditioning`, 'heat')":
"accessory.addService(api.hap.Service.HeaterCooler, 'BMW Preconditioning', 'heat')",

"accessory.addService(api.hap.Service.ContactSensor, `${name} Doors`, 'doors')":
"accessory.addService(api.hap.Service.ContactSensor, 'BMW Doors', 'doors')",

"accessory.addService(api.hap.Service.ContactSensor, `${name} Windows`, 'windows')":
"accessory.addService(api.hap.Service.ContactSensor, 'BMW Windows', 'windows')",

"accessory.addService(api.hap.Service.ContactSensor, `${name} Boot`, 'boot')":
"accessory.addService(api.hap.Service.ContactSensor, 'BMW Boot', 'boot')",

"accessory.addService(api.hap.Service.Switch, `${name} Tyres OK`, 'tyres')":
"accessory.addService(api.hap.Service.Switch, 'BMW Tyres', 'tyres')",
}

for old, new in replacements.items():
    s = s.replace(old, new)

# Add explicit name setting after services are assigned.
marker = """    this.setupHandlers();
    this.fetchAndUpdate();"""

name_block = """    this.setServiceName(this.lockService, 'BMW Lock');
    this.setServiceName(this.batteryService, 'BMW Battery');
    this.setServiceName(this.heaterService, 'BMW Preconditioning');
    this.setServiceName(this.doorsService, 'BMW Doors');
    this.setServiceName(this.windowsService, 'BMW Windows');
    this.setServiceName(this.bootService, 'BMW Boot');
    this.setServiceName(this.tyresService, 'BMW Tyres');

"""

if "this.setServiceName(this.doorsService, 'BMW Doors');" not in s:
    s = s.replace(marker, name_block + marker)

p.write_text(s)
PY

npm install
npm run build

node - <<'NODE'
const fs = require('fs');
const s = fs.readFileSync('dist/vehicleAccessory.js', 'utf8');
for (const term of [
  'BMW Battery',
  'BMW Doors',
  'BMW Windows',
  'BMW Boot',
  'BMW Tyres',
  'BMW Lock',
  'BMW Preconditioning',
  'setServiceName',
  'ConfiguredName'
]) {
  if (!s.includes(term)) throw new Error(term + ' missing');
}
console.log('Validation OK');
NODE

npm pack --dry-run

git add package.json package-lock.json src/vehicleAccessory.ts
git add -u package.json package-lock.json src/vehicleAccessory.ts

git commit -m "Set human-readable HomeKit tile names"
git push -u origin "$(git branch --show-current)"

npm publish
npm view homebridge-bmhome@0.1.0-beta.27 version description

echo "== BMHome beta.27 complete =="
