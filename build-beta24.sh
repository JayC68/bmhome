set -euo pipefail

cd /Users/Jon/bmhome
echo "== BMHome v0.1.0-beta.24 HomeKit service tiles =="

npm login
npm whoami
rm -f homebridge-bmhome-*.tgz

echo "1. Set version"
node - <<'NODE'
const fs = require('fs');
const p = 'package.json';
const pkg = JSON.parse(fs.readFileSync(p, 'utf8'));
pkg.version = '0.1.0-beta.24';
pkg.repository = { type: 'git', url: 'git+https://github.com/JayC68/bmhome.git' };
pkg.bugs = { url: 'https://github.com/JayC68/bmhome/issues' };
pkg.homepage = 'https://bmhome.kernowekconsulting.co.uk';
fs.writeFileSync(p, JSON.stringify(pkg, null, 2) + '\n');
NODE

echo "2. Patch BMWClient boot split"
python3 <<'PY'
from pathlib import Path

p = Path("src/bmwClient.ts")
s = p.read_text()

s = s.replace(
"""      const doorsOpen = anyTrue([
        'vehicle.cabin.door.row1.driver.isOpen',
        'vehicle.cabin.door.row1.passenger.isOpen',
        'vehicle.cabin.door.row2.driver.isOpen',
        'vehicle.cabin.door.row2.passenger.isOpen',
        'vehicle.body.trunk.door.isOpen',
        'vehicle.body.trunk.isOpen',
        'vehicle.body.tailgate.isOpen'
      ]);""",
"""      const doorsOpen = anyTrue([
        'vehicle.cabin.door.row1.driver.isOpen',
        'vehicle.cabin.door.row1.passenger.isOpen',
        'vehicle.cabin.door.row2.driver.isOpen',
        'vehicle.cabin.door.row2.passenger.isOpen'
      ]);

      const bootOpen = anyNotClosed([
        'vehicle.body.trunk.door.isOpen',
        'vehicle.body.trunk.isOpen',
        'vehicle.body.tailgate.isOpen'
      ]);"""
)

s = s.replace(
"""        doorsOpen,
        windowsOpen,""",
"""        doorsOpen,
        bootOpen,
        windowsOpen,"""
)

s = s.replace(
"""        `DoorsOpen=${data.doorsOpen ?? 'unknown'} ` +
        `WindowsOpen=${data.windowsOpen ?? 'unknown'} ` +""",
"""        `DoorsOpen=${data.doorsOpen ?? 'unknown'} ` +
        `WindowsOpen=${data.windowsOpen ?? 'unknown'} ` +
        `BootOpen=${data.bootOpen ?? 'unknown'} ` +"""
)

p.write_text(s)
PY

echo "3. Replace vehicleAccessory HomeKit services"
cat > src/vehicleAccessory.ts <<'TS'
import { API, Logging, PlatformAccessory, Service } from 'homebridge';
import { BMWClient } from './bmwClient';
import { VehicleData } from './types';

export class VehicleAccessory {
  private readonly log: Logging;
  private readonly api: API;
  private readonly client: BMWClient;
  private readonly vin: string;
  private readonly pollingInterval: number;

  private lockService!: Service;
  private batteryService!: Service;
  private heaterService!: Service;
  private doorsService!: Service;
  private windowsService!: Service;
  private bootService!: Service;
  private tyresService!: Service;

  constructor(
    log: Logging,
    api: API,
    client: BMWClient,
    vin: string,
    name: string,
    existingAccessory?: PlatformAccessory,
  ) {
    this.log = log;
    this.api = api;
    this.client = client;
    this.vin = vin;
    this.pollingInterval = (client.config?.pollingInterval ?? 180) * 1000;

    let accessory: PlatformAccessory;

    if (existingAccessory) {
      accessory = existingAccessory;
      this.log.info(`Restoring accessory from cache: ${name}`);
    } else {
      accessory = new api.platformAccessory(name, api.hap.uuid.generate(`bmhome-${vin || 'auto'}`));
      api.registerPlatformAccessories('homebridge-bmhome', 'BMWHome', [accessory]);
      this.log.info(`Registered new accessory: ${name}`);
    }

    accessory.getService(api.hap.Service.AccessoryInformation)!
      .setCharacteristic(api.hap.Characteristic.Manufacturer, 'BMW Group')
      .setCharacteristic(api.hap.Characteristic.Model, 'BMW / MINI Vehicle')
      .setCharacteristic(api.hap.Characteristic.SerialNumber, vin || 'auto');

    this.lockService =
      accessory.getService(api.hap.Service.LockMechanism) ??
      accessory.addService(api.hap.Service.LockMechanism, `${name} Lock`, 'lock');

    this.batteryService =
      accessory.getService(api.hap.Service.Battery) ??
      accessory.addService(api.hap.Service.Battery, `${name} Battery`, 'battery');

    this.heaterService =
      accessory.getService(api.hap.Service.HeaterCooler) ??
      accessory.addService(api.hap.Service.HeaterCooler, `${name} Preconditioning`, 'heat');

    this.doorsService =
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
      accessory.addService(api.hap.Service.Switch, `${name} Tyres OK`, 'tyres');

    this.setupHandlers();
    this.fetchAndUpdate();
    this.startPolling();
  }

  private setupHandlers(): void {
    const { Characteristic } = this.api.hap;

    this.lockService
      .getCharacteristic(Characteristic.LockTargetState)
      .onSet(async (value) => {
        const result = value === Characteristic.LockTargetState.SECURED
          ? await this.client.lock(this.vin)
          : await this.client.unlock(this.vin);

        this.log.warn(result.message);
      });

    this.heaterService
      .getCharacteristic(Characteristic.Active)
      .onSet(async (value) => {
        const result = await this.client.precondition(
          this.vin,
          value === Characteristic.Active.ACTIVE,
        );

        this.log.warn(result.message);
      });

    this.tyresService
      .getCharacteristic(Characteristic.On)
      .onSet(() => {
        // Read-only semantic switch. Reverted on next update.
        this.log.info('Tyres OK is read-only; BMW tyre pressure data controls this tile.');
      });
  }

  private async fetchAndUpdate(): Promise<void> {
    try {
      const data = await this.client.getVehicleData(this.vin);
      if (data) {
        this.updateCharacteristics(data);
      }
    } catch (err) {
      this.log.error('Vehicle data fetch failed', err);
    }
  }

  private startPolling(): void {
    setInterval(() => this.fetchAndUpdate(), this.pollingInterval);
  }

  private updateContact(service: Service, open: boolean | undefined): void {
    const { Characteristic } = this.api.hap;

    if (open === undefined) {
      return;
    }

    service.updateCharacteristic(
      Characteristic.ContactSensorState,
      open
        ? Characteristic.ContactSensorState.CONTACT_NOT_DETECTED
        : Characteristic.ContactSensorState.CONTACT_DETECTED,
    );
  }

  private updateCharacteristics(data: VehicleData): void {
    const { Characteristic } = this.api.hap;

    if (data.lockStatus && data.lockStatus !== 'unknown') {
      const isLocked = data.lockStatus === 'locked' || data.lockStatus === 'LOCKED';

      this.lockService.updateCharacteristic(
        Characteristic.LockCurrentState,
        isLocked ? Characteristic.LockCurrentState.SECURED : Characteristic.LockCurrentState.UNSECURED,
      );

      this.lockService.updateCharacteristic(
        Characteristic.LockTargetState,
        isLocked ? Characteristic.LockTargetState.SECURED : Characteristic.LockTargetState.UNSECURED,
      );
    }

    if (data.soc !== undefined) {
      this.batteryService.updateCharacteristic(Characteristic.BatteryLevel, data.soc);
      this.batteryService.updateCharacteristic(
        Characteristic.StatusLowBattery,
        data.soc < 20
          ? Characteristic.StatusLowBattery.BATTERY_LEVEL_LOW
          : Characteristic.StatusLowBattery.BATTERY_LEVEL_NORMAL,
      );
    }

    if (data.isCharging !== undefined || data.chargingStatus !== undefined) {
      const status = String(data.chargingStatus || '').toLowerCase();
      const isCharging = data.isCharging === true || status.includes('charging');

      this.batteryService.updateCharacteristic(
        Characteristic.ChargingState,
        isCharging
          ? Characteristic.ChargingState.CHARGING
          : Characteristic.ChargingState.NOT_CHARGING,
      );
    }

    if (data.preconditionActive !== undefined) {
      this.heaterService.updateCharacteristic(
        Characteristic.Active,
        data.preconditionActive ? Characteristic.Active.ACTIVE : Characteristic.Active.INACTIVE,
      );
    }

    this.updateContact(this.doorsService, data.doorsOpen);
    this.updateContact(this.windowsService, data.windowsOpen);
    this.updateContact(this.bootService, data.bootOpen);

    if (data.tyresOk !== undefined) {
      this.tyresService.updateCharacteristic(Characteristic.On, data.tyresOk);
    }

    this.log.debug(`Characteristics updated for VIN: ${data.vin ?? this.vin}`);
  }
}
TS

echo "4. Patch VehicleData types"
python3 <<'PY'
from pathlib import Path

p = Path("src/types.ts")
s = p.read_text()

replacements = {
  "remainingRange?: number;": "remainingRange?: number;\n  remainingRangeKm?: number;\n  remainingRangeMiles?: number;\n  distanceUnit?: 'mi' | 'km';",
  "isCharging?: boolean;": "isCharging?: boolean;\n  pluggedIn?: boolean;\n  chargingPortStatus?: string;\n  chargingPower?: number;",
  "lockStatus?: 'locked' | 'unlocked' | 'unknown';": "lockStatus?: 'locked' | 'unlocked' | 'unknown' | 'LOCKED' | 'UNLOCKED';\n  locked?: boolean;",
  "preconditionActive?: boolean;": "preconditionActive?: boolean;\n  doorsOpen?: boolean;\n  windowsOpen?: boolean;\n  bootOpen?: boolean;\n  tyrePressures?: number[];\n  tyresOk?: boolean;\n  vehicleBrand?: 'BMW' | 'MINI';\n  rawDescriptors?: unknown;",
}

for old, new in replacements.items():
    if old in s and new not in s:
        s = s.replace(old, new)

p.write_text(s)
PY

echo "5. Build"
npm install
npm run build

echo "6. Validate"
node - <<'NODE'
const fs = require('fs');

const accessory = fs.readFileSync('dist/vehicleAccessory.js', 'utf8');
const client = fs.readFileSync('dist/bmwClient.js', 'utf8');

for (const term of [
  'ContactSensor',
  'Doors',
  'Windows',
  'Boot',
  'Tyres OK',
  'ContactSensorState',
]) {
  if (!accessory.includes(term)) throw new Error(term + ' missing from vehicleAccessory');
}

for (const term of [
  'bootOpen',
  'BootOpen=',
  'TyresOk=',
  'clampHomeKitBatteryLevel',
]) {
  if (!client.includes(term)) throw new Error(term + ' missing from bmwClient');
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

git commit -m "Add HomeKit contact and tyre status services"

echo "9. Push to GitHub first"
git push -u origin "$(git branch --show-current)"

echo "10. Publish to npm"
npm publish

echo "11. Verify npm"
npm view homebridge-bmhome@0.1.0-beta.24 version description

echo "== BMHome beta.24 complete =="
