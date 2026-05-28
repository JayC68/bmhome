set -euo pipefail

cd /Users/Jon/bmhome

echo "== BMHome v0.1.0-beta.14 descriptor payload mapper =="

npm login
npm whoami

rm -f homebridge-bmhome-*.tgz

node - <<'NODE'
const fs = require('fs');
const p = 'package.json';
const pkg = JSON.parse(fs.readFileSync(p, 'utf8'));
pkg.version = '0.1.0-beta.14';
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

if "private descriptorState" not in s:
    s = s.replace(
        "export class BMWClient {",
        "export class BMWClient {\n  private descriptorState: Record<string, any> = {};\n",
        1
    )

new_method = r'''  private handleMqttMessage(topic: string, payload: Buffer): void {
    try {
      const text = payload.toString('utf8');
      const json = JSON.parse(text);
      const vin = this.extractVin(topic, json);

      if (json?.data && typeof json.data === 'object') {
        Object.assign(this.descriptorState, json.data);
      }

      const value = (path: string): any => {
        const entry = this.descriptorState[path];
        return entry && typeof entry === 'object' ? entry.value : undefined;
      };

      const anyTrue = (paths: string[]): boolean | undefined => {
        let seen = false;
        for (const path of paths) {
          const v = value(path);
          if (v === undefined) continue;
          seen = true;
          if (v === true || v === 'OPEN' || v === 'OPENED') return true;
        }
        return seen ? false : undefined;
      };

      const anyNotClosed = (paths: string[]): boolean | undefined => {
        let seen = false;
        for (const path of paths) {
          const v = value(path);
          if (v === undefined) continue;
          seen = true;
          if (v !== false && v !== 'CLOSED' && v !== 'CLOSE') return true;
        }
        return seen ? false : undefined;
      };

      const soc =
        value('vehicle.drivetrain.highVoltageBattery.stateOfCharge') ??
        value('vehicle.drivetrain.highVoltageBattery.soc');

      const remainingRange =
        value('vehicle.drivetrain.electricEngine.kombiRemainingElectricRange') ??
        value('vehicle.drivetrain.lastRemainingRange');

      const lockRaw =
        value('vehicle.security.centralLock.status') ??
        value('vehicle.vehicle.lock.status');

      const locked =
        lockRaw === 'LOCKED' || lockRaw === 'SECURED' || lockRaw === true
          ? true
          : lockRaw === 'UNLOCKED' || lockRaw === false
            ? false
            : undefined;

      const doorsOpen = anyTrue([
        'vehicle.cabin.door.row1.driver.isOpen',
        'vehicle.cabin.door.row1.passenger.isOpen',
        'vehicle.cabin.door.row2.driver.isOpen',
        'vehicle.cabin.door.row2.passenger.isOpen',
        'vehicle.body.trunk.door.isOpen',
        'vehicle.body.tailgate.isOpen'
      ]);

      const windowsOpen = anyNotClosed([
        'vehicle.cabin.window.row1.driver.status',
        'vehicle.cabin.window.row1.passenger.status',
        'vehicle.cabin.window.row2.driver.status',
        'vehicle.cabin.window.row2.passenger.status',
        'vehicle.cabin.sunroof.status'
      ]);

      const tyrePressures = [
        value('vehicle.chassis.axle.row1.wheel.left.tire.pressure'),
        value('vehicle.chassis.axle.row1.wheel.right.tire.pressure'),
        value('vehicle.chassis.axle.row2.wheel.left.tire.pressure'),
        value('vehicle.chassis.axle.row2.wheel.right.tire.pressure')
      ].filter((v) => typeof v === 'number');

      const data: any = {
        vin,
        soc: typeof soc === 'number' ? soc : undefined,
        remainingRange: typeof remainingRange === 'number' ? remainingRange : undefined,
        isCharging: undefined,
        chargingStatus: undefined,
        lockStatus: locked === true ? 'LOCKED' : locked === false ? 'UNLOCKED' : undefined,
        locked,
        doorsOpen,
        windowsOpen,
        tyrePressures,
        raw: json,
        rawDescriptors: this.descriptorState,
        timestamp: new Date(),
      };

      this.latestVehicleData = data;

      console.log(`[BMWClient] MQTT vehicle update received for ${vin}`);
      console.log(
        `[BMWClient] Parsed vehicle state: ` +
        `SOC=${data.soc ?? 'unknown'} ` +
        `Range=${data.remainingRange ?? 'unknown'} ` +
        `Charging=${data.isCharging ?? 'unknown'} ` +
        `Lock=${data.lockStatus ?? 'unknown'} ` +
        `DoorsOpen=${data.doorsOpen ?? 'unknown'} ` +
        `WindowsOpen=${data.windowsOpen ?? 'unknown'} ` +
        `Tyres=${tyrePressures.length}/4`
      );
    } catch (err: any) {
      console.error(`[BMWClient] Failed to parse MQTT payload: ${err?.message || err}`);
    }
  }
'''

s2 = re.sub(
    r"  private handleMqttMessage\(topic: string, payload: Buffer\): void \{[\s\S]*?\n  private extractVin",
    new_method + "\n  private extractVin",
    s,
    count=1
)

if s2 == s:
    raise SystemExit("Could not replace handleMqttMessage")

p.write_text(s2)
PY

npm install
npm run build

node - <<'NODE'
const fs = require('fs');
const s = fs.readFileSync('dist/bmwClient.js', 'utf8');
if (!s.includes('descriptorState')) throw new Error('descriptorState missing from dist');
if (!s.includes('kombiRemainingElectricRange')) throw new Error('range mapper missing');
if (!s.includes('DoorsOpen=')) throw new Error('new parsed state log missing');
if (!s.includes('Tyres=')) throw new Error('tyre mapper log missing');
console.log('Validation OK');
NODE

npm pack --dry-run

git add package.json package-lock.json src/bmwClient.ts
git add -u package.json package-lock.json src/bmwClient.ts
git commit -m "Map BMW descriptor payloads into live vehicle state"

git push -u origin "$(git branch --show-current)"

npm publish

npm view homebridge-bmhome@0.1.0-beta.14 version description

echo "== BMHome beta.14 complete =="
