set -euo pipefail

REPO="/Users/Jon/bmhome"
VERSION="0.1.0-beta.13"

cd "$REPO"

echo "== BMHome ${VERSION} payload mapper =="

echo "1. npm login"
npm login
npm whoami

echo "2. Clean tarballs"
rm -f homebridge-bmhome-*.tgz

echo "3. Set package version"
node <<'NODE'
const fs = require('fs');
const p = 'package.json';
const pkg = JSON.parse(fs.readFileSync(p, 'utf8'));

pkg.version = '0.1.0-beta.13';
pkg.repository = { type: 'git', url: 'git+https://github.com/JayC68/bmhome.git' };
pkg.bugs = { url: 'https://github.com/JayC68/bmhome/issues' };
pkg.homepage = 'https://bmhome.kernowekconsulting.co.uk';

fs.writeFileSync(p, JSON.stringify(pkg, null, 2) + '\n');
console.log(pkg.name + '@' + pkg.version);
NODE

echo "4. Patch bmwClient payload mapping"
node <<'NODE'
const fs = require('fs');
const p = 'src/bmwClient.ts';
let s = fs.readFileSync(p, 'utf8');

if (!s.includes('private descriptorState')) {
  s = s.replace(
    'export class BMWClient {',
    `export class BMWClient {
  private descriptorState: Record<string, any> = {};
`
  );
}

if (!s.includes('private valueForDescriptor')) {
  s = s.replace(
    /(\n\s*async getVehicleData[\s\S]*?\n\s*}\n)/,
    `
  private valueForDescriptor(path: string): any {
    const entry = this.descriptorState[path];
    if (!entry || typeof entry !== 'object') {
      return undefined;
    }
    return entry.value;
  }

  private hasAnyTrue(paths: string[]): boolean | undefined {
    let seen = false;

    for (const path of paths) {
      const value = this.valueForDescriptor(path);
      if (value === undefined) {
        continue;
      }

      seen = true;

      if (value === true || value === 'OPEN' || value === 'OPENED') {
        return true;
      }
    }

    return seen ? false : undefined;
  }

  private hasAnyNotClosed(paths: string[]): boolean | undefined {
    let seen = false;

    for (const path of paths) {
      const value = this.valueForDescriptor(path);
      if (value === undefined) {
        continue;
      }

      seen = true;

      if (value !== false && value !== 'CLOSED' && value !== 'CLOSE' && value !== 'INVALID') {
        return true;
      }
    }

    return seen ? false : undefined;
  }

  private updateVehicleStateFromDescriptors(vin: string): void {
    const soc =
      this.valueForDescriptor('vehicle.drivetrain.highVoltageBattery.stateOfCharge') ??
      this.valueForDescriptor('vehicle.drivetrain.highVoltageBattery.soc');

    const remainingRange =
      this.valueForDescriptor('vehicle.drivetrain.electricEngine.kombiRemainingElectricRange') ??
      this.valueForDescriptor('vehicle.drivetrain.lastRemainingRange');

    const chargingStatus =
      this.valueForDescriptor('vehicle.drivetrain.charging.status') ??
      this.valueForDescriptor('vehicle.drivetrain.charging.isCharging');

    const lockValue =
      this.valueForDescriptor('vehicle.security.centralLock.status') ??
      this.valueForDescriptor('vehicle.vehicle.lock.status');

    const doorsOpen = this.hasAnyTrue([
      'vehicle.cabin.door.row1.driver.isOpen',
      'vehicle.cabin.door.row1.passenger.isOpen',
      'vehicle.cabin.door.row2.driver.isOpen',
      'vehicle.cabin.door.row2.passenger.isOpen',
      'vehicle.body.trunk.door.isOpen',
      'vehicle.body.tailgate.isOpen'
    ]);

    const windowsOpen = this.hasAnyNotClosed([
      'vehicle.cabin.window.row1.driver.status',
      'vehicle.cabin.window.row1.passenger.status',
      'vehicle.cabin.window.row2.driver.status',
      'vehicle.cabin.window.row2.passenger.status',
      'vehicle.cabin.sunroof.status'
    ]);

    const alarmActive =
      this.valueForDescriptor('vehicle.vehicle.antiTheftAlarmSystem.alarm.isOn') ??
      this.valueForDescriptor('vehicle.security.alarm.isActive');

    const tyrePressures = [
      this.valueForDescriptor('vehicle.chassis.axle.row1.wheel.left.tire.pressure'),
      this.valueForDescriptor('vehicle.chassis.axle.row1.wheel.right.tire.pressure'),
      this.valueForDescriptor('vehicle.chassis.axle.row2.wheel.left.tire.pressure'),
      this.valueForDescriptor('vehicle.chassis.axle.row2.wheel.right.tire.pressure')
    ].filter(v => typeof v === 'number');

    const locked =
      lockValue === 'LOCKED' || lockValue === 'SECURED' || lockValue === true
        ? true
        : lockValue === 'UNLOCKED' || lockValue === false
          ? false
          : undefined;

    const charging =
      chargingStatus === true ||
      chargingStatus === 'CHARGING' ||
      chargingStatus === 'ACTIVE';

    this.latestVehicleData = {
      vin,
      soc: typeof soc === 'number' ? soc : undefined,
      remainingRange: typeof remainingRange === 'number' ? remainingRange : undefined,
      charging,
      locked,
      doorsOpen,
      windowsOpen,
      alarmActive: Boolean(alarmActive),
      tyrePressures,
      rawDescriptors: this.descriptorState
    };

    console.log(
      \`[BMWClient] Parsed vehicle state: SOC=\${this.latestVehicleData.soc ?? 'unknown'} ` +
      \`Range=\${this.latestVehicleData.remainingRange ?? 'unknown'} ` +
      \`Charging=\${this.latestVehicleData.charging ?? 'unknown'} ` +
      \`Lock=\${this.latestVehicleData.locked ?? 'unknown'} ` +
      \`DoorsOpen=\${this.latestVehicleData.doorsOpen ?? 'unknown'} ` +
      \`WindowsOpen=\${this.latestVehicleData.windowsOpen ?? 'unknown'} ` +
      \`Tyres=\${tyrePressures.length}/4\`
    );
  }
$1`
  );
}

s = s.replace(
  /this\.latestVehicleData = parsed;\s*/g,
  `if (parsed && parsed.data && typeof parsed.data === 'object') {
          Object.assign(this.descriptorState, parsed.data);
          this.updateVehicleStateFromDescriptors(parsed.vin || this.config.vin || 'unknown');
        } else {
          this.latestVehicleData = parsed;
        }
`
);

s = s.replace(
  /console\.log\(`$begin:math:display$BMWClient$end:math:display$ Parsed vehicle state: SOC=\$\{[^;]+?;\n/g,
  ''
);

fs.writeFileSync(p, s);
NODE

echo "5. Build"
npm install
npm run build

echo "6. Validate"
node <<'NODE'
const fs = require('fs');
const s = fs.readFileSync('src/bmwClient.ts', 'utf8');

function fail(msg) {
  console.error('FAIL: ' + msg);
  process.exit(1);
}

if (!s.includes('private descriptorState')) fail('descriptorState missing');
if (!s.includes('updateVehicleStateFromDescriptors')) fail('mapper missing');
if (!s.includes('vehicle.cabin.window.row1.driver.status')) fail('window descriptor missing');
if (!s.includes('vehicle.cabin.door.row1.driver.isOpen')) fail('door descriptor missing');
if (!s.includes('kombiRemainingElectricRange')) fail('range descriptor missing');
if (!s.includes('tire.pressure')) fail('tyre pressure descriptor missing');
if (!s.includes('password: this.tokenStore.idToken')) fail('BMW doc idToken MQTT password missing');
if (!s.includes('${this.tokenStore.gcid}/${this.config.vin')) fail('BMW doc gcid/VIN topic missing');

console.log('Validation OK');
NODE

echo "7. Package dry run"
npm pack --dry-run

echo "8. Commit"
git add package.json package-lock.json src/bmwClient.ts
git add -u package.json package-lock.json src/bmwClient.ts

if git diff --cached --quiet; then
  echo "No staged release changes; stopping."
  exit 1
fi

git commit -m "Map BMW CarData MQTT payloads into vehicle state"

echo "9. Push to GitHub first"
git push -u origin "$(git branch --show-current)"

echo "10. Publish to npm"
npm publish

echo "11. Verify"
npm view homebridge-bmhome@0.1.0-beta.13 version description

echo "== BMHome beta.13 complete =="
