set -euo pipefail

cd /Users/Jon/bmhome

echo "== BMHome v0.1.0-beta.19 auto brand and fuel parser =="

npm login
npm whoami

rm -f homebridge-bmhome-*.tgz

node - <<'NODE'
const fs = require('fs');
const p = 'package.json';
const pkg = JSON.parse(fs.readFileSync(p, 'utf8'));
pkg.version = '0.1.0-beta.19';
pkg.repository = { type: 'git', url: 'git+https://github.com/JayC68/bmhome.git' };
pkg.bugs = { url: 'https://github.com/JayC68/bmhome/issues' };
pkg.homepage = 'https://bmhome.kernowekconsulting.co.uk';
fs.writeFileSync(p, JSON.stringify(pkg, null, 2) + '\n');
NODE

python3 <<'PY'
from pathlib import Path
import re

p = Path("src/bmwClient.ts")
s = p.read_text()

if "private detectVehicleBrand" not in s:
    s = s.replace(
        "  private shouldLogEvery",
"""  private detectVehicleBrand(vin?: string): 'BMW' | 'MINI' {
    const wmi = (vin || '').slice(0, 3).toUpperCase();
    return wmi === 'WMW' ? 'MINI' : 'BMW';
  }

  private shouldLogEvery"""
    )

if "remainingFuel" not in s:
    s = s.replace(
"""      const remainingRange =
        value('vehicle.drivetrain.electricEngine.kombiRemainingElectricRange') ??
        value('vehicle.drivetrain.lastRemainingRange');""",
"""      const remainingRange =
        value('vehicle.drivetrain.electricEngine.kombiRemainingElectricRange') ??
        value('vehicle.drivetrain.lastRemainingRange');

      const remainingFuel =
        value('vehicle.drivetrain.fuelSystem.remainingFuel');"""
    )

s = s.replace(
"""        distanceUnit,""",
"""        distanceUnit,
        remainingFuel: typeof remainingFuel === 'number' ? remainingFuel : undefined,
        vehicleBrand: this.detectVehicleBrand(vin),"""
)

s = s.replace(
"""        `Tyres=${tyrePressures.length}/4`;""",
"""        `Tyres=${tyrePressures.length}/4 ` +
        `Brand=${data.vehicleBrand}` +
        `${data.remainingFuel !== undefined ? ` Fuel=${data.remainingFuel}` : ''}`;"""
)

p.write_text(s)
PY

npm install
npm run build

node - <<'NODE'
const fs = require('fs');
const s = fs.readFileSync('dist/bmwClient.js', 'utf8');
if (!s.includes('detectVehicleBrand')) throw new Error('brand detection missing');
if (!s.includes('vehicle.drivetrain.fuelSystem.remainingFuel')) throw new Error('fuel descriptor missing');
if (!s.includes('WMW')) throw new Error('MINI WMI missing');
if (s.includes('MQTT RAW PAYLOAD START')) throw new Error('raw payload spam returned');
if (s.includes('MQTT vehicle update received')) throw new Error('update spam returned');
console.log('Validation OK');
NODE

npm pack --dry-run

git add package.json package-lock.json src/bmwClient.ts
git add -u package.json package-lock.json src/bmwClient.ts

git commit -m "Add auto brand detection and fuel descriptor parsing"

git push -u origin "$(git branch --show-current)"

npm publish

npm view homebridge-bmhome@0.1.0-beta.19 version description

echo "== BMHome beta.19 complete =="
