set -euo pipefail

cd /Users/Jon/bmhome
echo "== BMHome v0.1.0-beta.23 HomeKit UX polish =="

npm login
npm whoami
rm -f homebridge-bmhome-*.tgz

echo "1. Set version"
node - <<'NODE'
const fs = require('fs');
const p = 'package.json';
const pkg = JSON.parse(fs.readFileSync(p, 'utf8'));
pkg.version = '0.1.0-beta.23';
pkg.repository = { type: 'git', url: 'git+https://github.com/JayC68/bmhome.git' };
pkg.bugs = { url: 'https://github.com/JayC68/bmhome/issues' };
pkg.homepage = 'https://bmhome.kernowekconsulting.co.uk';
fs.writeFileSync(p, JSON.stringify(pkg, null, 2) + '\n');
NODE

echo "2. Patch BMWClient derived HomeKit-friendly state"
python3 <<'PY'
from pathlib import Path
import re

p = Path("src/bmwClient.ts")
s = p.read_text()

# Add helper methods before detectVehicleBrand if not already present.
if "private clampHomeKitBatteryLevel" not in s:
    s = s.replace(
"""  private detectVehicleBrand""",
"""  private clampHomeKitBatteryLevel(value?: number): number | undefined {
    if (typeof value !== 'number' || !Number.isFinite(value)) {
      return undefined;
    }

    const rounded = Math.round(value);

    // Apple Home treats 0% and 100% awkwardly for battery-style tiles.
    // Show a useful visible range while preserving the real raw value separately.
    if (rounded <= 0) {
      return 1;
    }

    if (rounded >= 100) {
      return 99;
    }

    return rounded;
  }

  private tyresOk(pressures: number[]): boolean | undefined {
    if (!Array.isArray(pressures) || pressures.length < 4) {
      return undefined;
    }

    // Current BMW stream reports kPa. We use a deliberately broad sanity band
    // for a simple HomeKit OK/Not OK status rather than exposing noisy per-tyre tiles.
    return pressures.every((pressure) => pressure >= 180 && pressure <= 360);
  }

  private detectVehicleBrand"""
    )

# Preserve raw SOC while feeding clamped SOC to HomeKit.
s = s.replace(
"""      const soc =
        value('vehicle.drivetrain.batteryManagement.header') ??
        value('vehicle.trip.segment.end.drivetrain.batteryManagement.hvSoc') ??
        value('vehicle.drivetrain.highVoltageBattery.stateOfCharge') ??
        value('vehicle.drivetrain.highVoltageBattery.soc');""",
"""      const rawSoc =
        value('vehicle.drivetrain.batteryManagement.header') ??
        value('vehicle.trip.segment.end.drivetrain.batteryManagement.hvSoc') ??
        value('vehicle.drivetrain.highVoltageBattery.stateOfCharge') ??
        value('vehicle.drivetrain.highVoltageBattery.soc');

      const soc = this.clampHomeKitBatteryLevel(rawSoc);"""
)

# Add HomeKit-friendly derived fields.
s = s.replace(
"""        vin,
        soc:""",
"""        vin,
        rawSoc: typeof rawSoc === 'number' ? rawSoc : undefined,
        soc:"""
)

s = s.replace(
"""        tyrePressures,""",
"""        tyrePressures,
        tyresOk: this.tyresOk(tyrePressures),"""
)

# Improve log summary to show clamped/raw SOC and tyre OK summary.
s = s.replace(
"""        `SOC=${data.soc ?? 'unknown'} ` +""",
"""        `SOC=${data.soc ?? 'unknown'}${data.rawSoc !== undefined && data.rawSoc !== data.soc ? ` raw=${data.rawSoc}` : ''} ` +"""
)

s = s.replace(
"""        `Tyres=${tyrePressures.length}/4 ` +""",
"""        `Tyres=${tyrePressures.length}/4${data.tyresOk !== undefined ? ` TyresOk=${data.tyresOk}` : ''} ` +"""
)

p.write_text(s)
PY

echo "3. Patch types if present"
python3 <<'PY'
from pathlib import Path
import re

for p in [Path("src/types.ts"), Path("src/bmwClient.ts")]:
    if not p.exists():
        continue

    s = p.read_text()
    original = s

    if "rawSoc" not in s and re.search(r"interface\s+.*Vehicle.*Data|type\s+.*Vehicle.*Data", s):
        s = s.replace("soc?: number;", "soc?: number;\n  rawSoc?: number;")
    if "tyresOk" not in s and re.search(r"interface\s+.*Vehicle.*Data|type\s+.*Vehicle.*Data", s):
        s = s.replace("tyrePressures?: number[];", "tyrePressures?: number[];\n  tyresOk?: boolean;")

    if s != original:
        p.write_text(s)
        print(f"patched {p}")
PY

echo "4. Build"
npm install
npm run build

echo "5. Validate"
node - <<'NODE'
const fs = require('fs');
const s = fs.readFileSync('dist/bmwClient.js', 'utf8');

for (const term of [
  'clampHomeKitBatteryLevel',
  'tyresOk',
  'rawSoc',
  'TyresOk=',
  'vehicle.drivetrain.batteryManagement.header'
]) {
  if (!s.includes(term)) throw new Error(term + ' missing');
}

if (s.includes('Candidate battery/charge descriptor')) throw new Error('discovery logging returned');
if (s.includes('MQTT RAW PAYLOAD START')) throw new Error('raw payload spam returned');
if (s.includes('MQTT vehicle update received')) throw new Error('update spam returned');

console.log('Validation OK');
NODE

echo "6. Package dry run"
npm pack --dry-run

echo "7. Commit"
git add package.json package-lock.json src/bmwClient.ts src/types.ts
git add -u package.json package-lock.json src/bmwClient.ts src/types.ts

if git diff --cached --quiet; then
  echo "No staged release changes; stopping."
  exit 1
fi

git commit -m "Add HomeKit friendly SOC and tyre status derived state"

echo "8. Push to GitHub first"
git push -u origin "$(git branch --show-current)"

echo "9. Publish to npm"
npm publish

echo "10. Verify npm"
npm view homebridge-bmhome@0.1.0-beta.23 version description

echo "== BMHome beta.23 complete =="
