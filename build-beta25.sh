set -euo pipefail

cd /Users/Jon/bmhome
echo "== BMHome v0.1.0-beta.25 persisted last-known vehicle state =="

npm login
npm whoami
rm -f homebridge-bmhome-*.tgz

echo "1. Set version"
node - <<'NODE'
const fs = require('fs');
const p = 'package.json';
const pkg = JSON.parse(fs.readFileSync(p, 'utf8'));
pkg.version = '0.1.0-beta.25';
pkg.repository = { type: 'git', url: 'git+https://github.com/JayC68/bmhome.git' };
pkg.bugs = { url: 'https://github.com/JayC68/bmhome/issues' };
pkg.homepage = 'https://bmhome.kernowekconsulting.co.uk';
fs.writeFileSync(p, JSON.stringify(pkg, null, 2) + '\n');
NODE

echo "2. Patch BMWClient persistence"
python3 <<'PY'
from pathlib import Path

p = Path("src/bmwClient.ts")
s = p.read_text()

if "private readonly vehicleStateFile" not in s:
    s = s.replace(
"""  private readonly tokenFile: string;
  private latestVehicleData: VehicleData | null = null;""",
"""  private readonly tokenFile: string;
  private readonly vehicleStateFile: string;
  private latestVehicleData: VehicleData | null = null;"""
    )

s = s.replace(
"""    this.tokenFile = path.join(bmhomeDir, 'cardata-token-store.json');
    this.loadTokenStore();""",
"""    this.tokenFile = path.join(bmhomeDir, 'cardata-token-store.json');
    this.vehicleStateFile = path.join(bmhomeDir, 'last-vehicle-state.json');
    this.loadTokenStore();
    this.loadVehicleState();"""
)

if "private loadVehicleState" not in s:
    s = s.replace(
"""  private loadTokenStore(): void {""",
"""  private loadVehicleState(): void {
    try {
      if (!fs.existsSync(this.vehicleStateFile)) {
        return;
      }

      const parsed = JSON.parse(fs.readFileSync(this.vehicleStateFile, 'utf8'));

      if (!parsed || typeof parsed !== 'object') {
        return;
      }

      this.latestVehicleData = {
        ...parsed,
        timestamp: parsed.timestamp ? new Date(parsed.timestamp) : new Date(),
        restoredFromCache: true,
      } as VehicleData;

      console.log(`[BMWClient] Restored last known BMW state from local cache for VIN: ${this.latestVehicleData?.vin || this.config.vin || 'unknown'}`);
    } catch (err: any) {
      console.warn(`[BMWClient] Could not restore last vehicle state: ${err?.message || err}`);
    }
  }

  private saveVehicleState(data: VehicleData): void {
    try {
      const safeData = {
        ...data,
        raw: undefined,
        rawDescriptors: undefined,
        restoredFromCache: undefined,
        cachedAt: new Date().toISOString(),
      };

      fs.writeFileSync(this.vehicleStateFile, JSON.stringify(safeData, null, 2));

      try {
        fs.chmodSync(this.vehicleStateFile, 0o600);
      } catch {
        // Best effort only.
      }
    } catch (err: any) {
      console.warn(`[BMWClient] Could not save last vehicle state: ${err?.message || err}`);
    }
  }

  private loadTokenStore(): void {"""
    )

s = s.replace(
"""      this.latestVehicleData = data;""",
"""      this.latestVehicleData = data;
      this.saveVehicleState(data);"""
)

s = s.replace(
"""    if (this.latestVehicleData) {
      if (!requestedVin || this.latestVehicleData.vin === requestedVin) {
        return this.latestVehicleData;
      }
    }""",
"""    if (this.latestVehicleData) {
      if (!requestedVin || this.latestVehicleData.vin === requestedVin) {
        return this.latestVehicleData;
      }
    }"""
)

p.write_text(s)
PY

echo "3. Patch types"
python3 <<'PY'
from pathlib import Path

p = Path("src/types.ts")
s = p.read_text()

if "restoredFromCache" not in s:
    s = s.replace(
"  rawDescriptors?: unknown;\n  raw?: unknown;",
"  rawDescriptors?: unknown;\n  restoredFromCache?: boolean;\n  cachedAt?: string;\n  raw?: unknown;"
    )

p.write_text(s)
PY

echo "4. Patch VehicleAccessory stale/cache debug"
python3 <<'PY'
from pathlib import Path

p = Path("src/vehicleAccessory.ts")
s = p.read_text()

if "restoredFromCache" not in s:
    s = s.replace(
"""    this.log.debug(`Characteristics updated for VIN: ${data.vin ?? this.vin}`);""",
"""    this.log.debug(`Characteristics updated for VIN: ${data.vin ?? this.vin}${data.restoredFromCache ? ' (cached)' : ''}`);"""
    )

p.write_text(s)
PY

echo "5. Build"
npm install
npm run build

echo "6. Validate"
node - <<'NODE'
const fs = require('fs');
const client = fs.readFileSync('dist/bmwClient.js', 'utf8');
const types = fs.readFileSync('dist/types.js', 'utf8');
const accessory = fs.readFileSync('dist/vehicleAccessory.js', 'utf8');

for (const term of [
  'last-vehicle-state.json',
  'loadVehicleState',
  'saveVehicleState',
  'Restored last known BMW state',
  'restoredFromCache',
  'cachedAt'
]) {
  if (!client.includes(term) && !accessory.includes(term)) {
    throw new Error(term + ' missing');
  }
}

if (client.includes('Candidate battery/charge descriptor')) throw new Error('discovery logging returned');
if (client.includes('MQTT RAW PAYLOAD START')) throw new Error('raw payload spam returned');
if (client.includes('MQTT vehicle update received')) throw new Error('update spam returned');

console.log('Validation OK');
NODE

echo "7. Package dry run"
npm pack --dry-run

echo "8. Commit"
git add package.json package-lock.json src/bmwClient.ts src/types.ts src/vehicleAccessory.ts
git add -u package.json package-lock.json src/bmwClient.ts src/types.ts src/vehicleAccessory.ts

if git diff --cached --quiet; then
  echo "No staged release changes; stopping."
  exit 1
fi

git commit -m "Persist and restore last known BMW vehicle state"

echo "9. Push to GitHub first"
git push -u origin "$(git branch --show-current)"

echo "10. Publish to npm"
npm publish

echo "11. Verify npm"
npm view homebridge-bmhome@0.1.0-beta.25 version description

echo "== BMHome beta.25 complete =="
