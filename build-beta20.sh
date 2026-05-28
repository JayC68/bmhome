set -euo pipefail

cd /Users/Jon/bmhome
echo "== BMHome v0.1.0-beta.20 SOC and charging descriptors =="

npm login
npm whoami
rm -f homebridge-bmhome-*.tgz

node - <<'NODE'
const fs = require('fs');
const p = 'package.json';
const pkg = JSON.parse(fs.readFileSync(p, 'utf8'));
pkg.version = '0.1.0-beta.20';
pkg.repository = { type: 'git', url: 'git+https://github.com/JayC68/bmhome.git' };
pkg.bugs = { url: 'https://github.com/JayC68/bmhome/issues' };
pkg.homepage = 'https://bmhome.kernowekconsulting.co.uk';
fs.writeFileSync(p, JSON.stringify(pkg, null, 2) + '\n');
NODE

python3 <<'PY'
from pathlib import Path

p = Path("src/bmwClient.ts")
s = p.read_text()

s = s.replace(
"""      const soc =
        value('vehicle.drivetrain.highVoltageBattery.stateOfCharge') ??
        value('vehicle.drivetrain.highVoltageBattery.soc');""",
"""      const soc =
        value('vehicle.drivetrain.batteryManagement.header') ??
        value('vehicle.trip.segment.end.drivetrain.batteryManagement.hvSoc') ??
        value('vehicle.drivetrain.highVoltageBattery.stateOfCharge') ??
        value('vehicle.drivetrain.highVoltageBattery.soc');"""
)

s = s.replace(
"""      const lockRaw =
        value('vehicle.security.centralLock.status') ??
        value('vehicle.vehicle.lock.status');""",
"""      const chargingPortStatus = value('vehicle.body.chargingPort.status');
      const chargingPower = value('vehicle.powertrain.electric.battery.charging.power');

      const lockRaw =
        value('vehicle.security.centralLock.status') ??
        value('vehicle.vehicle.lock.status');"""
)

s = s.replace(
"""        'vehicle.body.trunk.door.isOpen',
        'vehicle.body.tailgate.isOpen'""",
"""        'vehicle.body.trunk.door.isOpen',
        'vehicle.body.trunk.isOpen',
        'vehicle.body.tailgate.isOpen'"""
)

s = s.replace(
"""        'vehicle.cabin.sunroof.status'""",
"""        'vehicle.cabin.sunroof.status',
        'vehicle.cabin.convertible.roofRetractableStatus'"""
)

s = s.replace(
"""        isCharging: undefined,
        chargingStatus: undefined,""",
"""        isCharging: typeof chargingPower === 'number' ? chargingPower > 0 : undefined,
        chargingStatus: typeof chargingPower === 'number' && chargingPower > 0 ? 'CHARGING' : undefined,
        chargingPortStatus,
        chargingPower: typeof chargingPower === 'number' ? chargingPower : undefined,
        pluggedIn: chargingPortStatus === 'CONNECTED',"""
)

s = s.replace(
"""        `Charging=${data.isCharging ?? 'unknown'} ` +""",
"""        `Charging=${data.isCharging ?? 'unknown'} ` +
        `PluggedIn=${data.pluggedIn ?? 'unknown'} ` +
        `${data.chargingPower !== undefined ? `ChargingPower=${data.chargingPower}W ` : ''}` +"""
)

p.write_text(s)
PY

npm install
npm run build

node - <<'NODE'
const fs = require('fs');
const s = fs.readFileSync('dist/bmwClient.js', 'utf8');
for (const term of [
  'vehicle.drivetrain.batteryManagement.header',
  'vehicle.trip.segment.end.drivetrain.batteryManagement.hvSoc',
  'vehicle.body.chargingPort.status',
  'vehicle.powertrain.electric.battery.charging.power',
  'vehicle.body.trunk.isOpen',
  'vehicle.cabin.convertible.roofRetractableStatus',
  'PluggedIn=',
  'ChargingPower='
]) {
  if (!s.includes(term)) throw new Error(term + ' missing');
}
if (s.includes('MQTT RAW PAYLOAD START')) throw new Error('raw payload spam returned');
if (s.includes('MQTT vehicle update received')) throw new Error('update spam returned');
console.log('Validation OK');
NODE

npm pack --dry-run

git add package.json package-lock.json src/bmwClient.ts
git add -u package.json package-lock.json src/bmwClient.ts
git commit -m "Add SOC charging plug and roof descriptor parsing"

git push -u origin "$(git branch --show-current)"

npm publish

npm view homebridge-bmhome@0.1.0-beta.20 version description

echo "== BMHome beta.20 complete =="
