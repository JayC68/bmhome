from pathlib import Path
import json

vehicle_accessory = r'''import { API, Logging, PlatformAccessory, Service } from 'homebridge';
import { BMWClient } from './bmwClient';
import { VehicleData } from './types';

export class VehicleAccessory {
  private readonly log: Logging;
  private readonly api: API;
  private readonly client: BMWClient;
  private readonly vin: string;
  private readonly pollingInterval: number;

  private batteryService!: Service;
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
      .setCharacteristic(api.hap.Characteristic.Model, 'BMW CarData Stream')
      .setCharacteristic(api.hap.Characteristic.SerialNumber, vin || 'auto');

    this.batteryService =
      accessory.getServiceById(api.hap.Service.Battery, 'battery') ??
      accessory.getService(api.hap.Service.Battery) ??
      accessory.addService(api.hap.Service.Battery, 'BMW Battery', 'battery');

    this.windowsService =
      accessory.getServiceById(api.hap.Service.ContactSensor, 'windows') ??
      accessory.addService(api.hap.Service.ContactSensor, 'BMW Windows', 'windows');

    this.bootService =
      accessory.getServiceById(api.hap.Service.ContactSensor, 'boot') ??
      accessory.addService(api.hap.Service.ContactSensor, 'BMW Boot', 'boot');

    this.tyresService =
      accessory.getServiceById(api.hap.Service.Switch, 'tyres') ??
      accessory.addService(api.hap.Service.Switch, 'BMW Tyres', 'tyres');

    this.setServiceName(this.batteryService, 'BMW Battery');
    this.setServiceName(this.windowsService, 'BMW Windows');
    this.setServiceName(this.bootService, 'BMW Boot');
    this.setServiceName(this.tyresService, 'BMW Tyres');

    this.fetchAndUpdate();
    this.startPolling();
  }

  private setServiceName(service: Service, name: string): void {
    const { Characteristic } = this.api.hap;
    service.setCharacteristic(Characteristic.Name, name);
    try { service.setCharacteristic(Characteristic.ConfiguredName, name); } catch {}
  }

  private async fetchAndUpdate(): Promise<void> {
    try {
      const data = await this.client.getVehicleData(this.vin);
      if (data) this.updateCharacteristics(data);
    } catch (err) {
      this.log.error('Vehicle data fetch failed', err);
    }
  }

  private startPolling(): void {
    setInterval(() => this.fetchAndUpdate(), this.pollingInterval);
  }

  private updateContact(service: Service, isOpen?: boolean): void {
    if (isOpen === undefined) return;
    const { Characteristic } = this.api.hap;
    service.updateCharacteristic(
      Characteristic.ContactSensorState,
      isOpen ? Characteristic.ContactSensorState.CONTACT_NOT_DETECTED : Characteristic.ContactSensorState.CONTACT_DETECTED,
    );
  }

  private updateCharacteristics(data: VehicleData): void {
    const { Characteristic } = this.api.hap;

    if (data.soc !== undefined) {
      this.batteryService.updateCharacteristic(Characteristic.BatteryLevel, data.soc);
      this.batteryService.updateCharacteristic(
        Characteristic.StatusLowBattery,
        data.soc < 20 ? Characteristic.StatusLowBattery.BATTERY_LEVEL_LOW : Characteristic.StatusLowBattery.BATTERY_LEVEL_NORMAL,
      );
    }

    if (data.isCharging !== undefined || data.chargingStatus !== undefined) {
      const status = String(data.chargingStatus || '').toLowerCase();
      const isCharging = data.isCharging === true || status.includes('charging');
      this.batteryService.updateCharacteristic(
        Characteristic.ChargingState,
        isCharging ? Characteristic.ChargingState.CHARGING : Characteristic.ChargingState.NOT_CHARGING,
      );
    }

    this.updateContact(this.windowsService, data.windowsOpen);
    this.updateContact(this.bootService, data.bootOpen);

    if (data.tyresOk !== undefined) {
      this.tyresService.updateCharacteristic(Characteristic.On, data.tyresOk);
    }

    this.log.debug(`Characteristics updated for VIN: ${data.vin ?? this.vin}`);
  }
}
'''

types_ts = r'''export interface BMHomePlatformConfig {
  distanceUnit?: 'mi' | 'km';
  platform?: string;
  name: string;
  clientId: string;
  vin?: string;
  enableStreaming: boolean;
  pollingInterval: number;
  storagePath?: string;
}

export interface VehicleData {
  vin: string;
  soc?: number;
  rawSoc?: number;
  remainingRange?: number;
  remainingRangeKm?: number;
  remainingRangeMiles?: number;
  distanceUnit?: 'mi' | 'km';
  isCharging?: boolean;
  pluggedIn?: boolean;
  chargingPortStatus?: string;
  chargingPower?: number;
  chargingStatus?: string;
  doorsOpen?: boolean;
  windowsOpen?: boolean;
  bootOpen?: boolean;
  tyrePressures?: number[];
  tyresOk?: boolean;
  vehicleBrand?: 'BMW' | 'MINI';
  remainingFuel?: number;
  rawDescriptors?: unknown;
  restoredFromCache?: boolean;
  cachedAt?: string;
  raw?: unknown;
  timestamp: Date;
}
'''

platform_ts = r'''import { API, DynamicPlatformPlugin, Logging, PlatformAccessory, PlatformConfig } from 'homebridge';
import { BMHomePlatformConfig } from './types';
import { BMWClient } from './bmwClient';
import { VehicleAccessory } from './vehicleAccessory';
import { validateConfig } from './configValidator';

export class BMWHomePlatform implements DynamicPlatformPlugin {
  private readonly log: Logging;
  private readonly api: API;
  private config!: BMHomePlatformConfig;
  private readonly accessories: PlatformAccessory[] = [];
  private client!: BMWClient;
  private configValid = false;

  constructor(log: Logging, config: PlatformConfig, api: API) {
    this.log = log;
    this.api = api;

    try {
      this.config = validateConfig(config);
      this.config.storagePath = this.api.user.storagePath();
      this.configValid = true;
      this.log.info(`BM Home Stream Platform loaded - Name: ${this.config.name}`);
    } catch (err: any) {
      this.log.error(`BM Home Stream config error: ${err.message}`);
      this.log.error('Plugin will not initialise until the config is corrected in the Homebridge UI.');
      return;
    }

    this.client = new BMWClient(this.config);

    api.on('didFinishLaunching', async () => {
      await this.onDidFinishLaunching();
    });
  }

  async onDidFinishLaunching(): Promise<void> {
    if (!this.configValid) {
      this.log.error('Skipping launch — invalid config.');
      return;
    }

    this.log.info('BM Home Stream didFinishLaunching');

    const success = await this.client.initialize();

    if (!success) {
      this.log.error('Failed to initialize BMW CarData client. Check Client ID and BMW authorisation logs.');
      return;
    }

    const vehicleName = this.config.name || 'BM Home Stream';
    const vin = this.config.vin || '';
    const uuid = this.api.hap.uuid.generate(`bmhome-${vin || 'auto'}`);

    const existingAccessory = this.accessories.find(a => a.UUID === uuid);

    if (existingAccessory) {
      this.log.info(`Restoring cached accessory: ${existingAccessory.displayName}`);
      new VehicleAccessory(this.log, this.api, this.client, vin, vehicleName, existingAccessory);
    } else {
      this.log.info(`Registering new accessory: ${vehicleName}`);
      new VehicleAccessory(this.log, this.api, this.client, vin, vehicleName);
    }
  }

  configureAccessory(accessory: PlatformAccessory): void {
    this.log.info(`Loading cached accessory: ${accessory.displayName}`);
    this.accessories.push(accessory);
  }
}
'''

# Clean bmwClient by transforming current file if present; source tree provides the known full file.
bmw_path = Path('src/bmwClient.ts')
bmw_client = bmw_path.read_text() if bmw_path.exists() else ''
if bmw_client:
    import re
    bmw_client = bmw_client.replace("import { BMHomePlatformConfig, VehicleData, CommandResponse } from './types';", "import { BMHomePlatformConfig, VehicleData } from './types';")
    bmw_client = re.sub(r"\n  async lock\([\s\S]*?\n  async startPreconditioning", "\n  async startPreconditioning", bmw_client)
    bmw_client = re.sub(r"\n  async startPreconditioning\([\s\S]*?\n  destroy\(\): void", "\n  destroy(): void", bmw_client)
    bmw_client = re.sub(r"\n      const lockRaw =[\s\S]*?const doorsOpen =", "\n      const doorsOpen =", bmw_client)
    bmw_client = re.sub(r"\n        lockStatus: [^\n]*\n        locked,", "", bmw_client)
    bmw_client = bmw_client.replace("        lockStatus: locked === true ? 'LOCKED' : locked === false ? 'UNLOCKED' : undefined,\n        locked,\n", "")
    bmw_client = re.sub(r"\n        `Lock=\$\{data\.lockStatus \?\? 'unknown'\} ` \+", "", bmw_client)
    bmw_client = re.sub(r"\n  private normaliseLockStatus\([\s\S]*?\n  private logAxiosError", "\n  private logAxiosError", bmw_client)
    bmw_client = bmw_client.replace('Initializing BMHome CarData client', 'Initializing BM Home Stream CarData client')
    bmw_client = bmw_client.replace('BMHome will retry quietly', 'BM Home Stream will retry quietly')
    bmw_client = bmw_client.replace('then restart BMHome.', 'then restart BM Home Stream.')
    bmw_client = bmw_client.replace('Homebridge/BMHome.', 'Homebridge/BM Home Stream.')
else:
    raise SystemExit('src/bmwClient.ts not found; run this from the repository root')

Path('src/vehicleAccessory.ts').write_text(vehicle_accessory)
Path('src/types.ts').write_text(types_ts)
Path('src/platform.ts').write_text(platform_ts)
Path('src/bmwClient.ts').write_text(bmw_client)

readme = r'''# BM Home Stream

**Your BMW telemetry, integrated into Apple Home.**

Fed by BMW’s CarData Stream.

BM Home Stream is a Homebridge plugin that brings selected BMW vehicle telemetry into Apple Home, so your car can sit alongside the rest of your HomeKit devices.

BM Home Stream is currently in public beta.

---

## What BM Home Stream Shows in Apple Home

BM Home Stream is designed to present useful BMW telemetry as simple Apple Home tiles:

- **BMW Battery** — battery state of charge when BMW publishes it
- **BMW Windows** — open / closed window status
- **BMW Boot** — boot / trunk open status
- **BMW Tyres** — simple OK / not OK tyre pressure status

BM Home Stream deliberately avoids cluttering Apple Home with raw technical telemetry.

---

## What BM Home Stream Is

BM Home Stream is a telemetry integration.

It listens to BMW CarData Stream and displays the data BMW publishes. It does not try to bypass BMW platform restrictions, and it does not pretend to provide vehicle control where BMW has not made that available to third-party integrations.

---

## Current Limitations

BMW currently limits third-party integrations primarily to telemetry exposed through BMW CarData Stream. BM Home Stream can only show the state BMW publishes.

- BMW CarData Stream is event-driven and can be delayed
- some descriptors may not be emitted by BMW for every vehicle
- the vehicle may stop publishing while asleep
- values may be stale until BMW emits a fresh event
- battery state of charge may be intermittent depending on descriptor availability
- lock/unlock, climate and other vehicle commands are not exposed by BM Home Stream

BM Home Stream only displays data BMW makes available through CarData Stream.

---

## Why BM Home Stream Does Not Lock or Unlock the Car

BMW CarData Stream is a telemetry-focused platform. Modern third-party CarData access provides vehicle data, but does not provide reliable third-party vehicle command support.

BMW’s own services can also report that vehicle status is temporarily unknown. For example, BMW may reject a lock or unlock action if door status is unknown to BMW’s backend.

BM Home Stream therefore does not expose a lock/unlock tile. A wrong lock state is worse than no lock state.

---

## BMW CarData Stream Setup

Sign in to BMW CarData using the same BMW ID used in the MyBMW app.

BMW UK CarData catalogue:

```text
https://www.bmw.co.uk/en-gb/mybmw/public/cardata-telematic-catalogue
```

Navigate to:

```text
Login
→ My Vehicle Overview
→ BMW CarData
→ CarData API
→ CarData Stream
```

Create or confirm your CarData client, then enable and save the descriptors BM Home Stream needs.

### Recommended Descriptors

```text
vehicle.drivetrain.batteryManagement.header
vehicle.drivetrain.electricEngine.kombiRemainingElectricRange
vehicle.drivetrain.lastRemainingRange

vehicle.body.trunk.isOpen
vehicle.body.trunk.door.isOpen

vehicle.cabin.window.row1.driver.status
vehicle.cabin.window.row1.passenger.status
vehicle.cabin.window.row2.driver.status
vehicle.cabin.window.row2.passenger.status
vehicle.cabin.sunroof.status

vehicle.chassis.axle.row1.wheel.left.tire.pressure
vehicle.chassis.axle.row1.wheel.right.tire.pressure
vehicle.chassis.axle.row2.wheel.left.tire.pressure
vehicle.chassis.axle.row2.wheel.right.tire.pressure

vehicle.body.chargingPort.status
vehicle.powertrain.electric.battery.charging.power
```

### Optional / Model-Specific Descriptors

```text
vehicle.trip.segment.end.drivetrain.batteryManagement.hvSoc
vehicle.drivetrain.fuelSystem.remainingFuel
vehicle.cabin.convertible.roofRetractableStatus
```

---

## Authorisation and Tokens

BM Home Stream stores BMW CarData tokens locally and normally refreshes them automatically.

Occasionally BMW may reject a stored refresh token. This can happen after a Homebridge restore, system rollback, account change, BMW backend change, or an expired authorisation flow.

When that happens BM Home Stream will show a new BMW authorisation link and one-time code in the Homebridge logs. Use the newest code shown.

---

## BMW Update Behaviour

BMW CarData Stream is not a constant live telemetry feed. Updates may be delayed, may depend on the vehicle waking, and may not include every descriptor every time.

BM Home Stream keeps the last known state locally so Apple Home can remain useful even when BMW is quiet.

---

## Disclaimer

BM Home Stream is an independent Homebridge plugin.

It is not affiliated with, endorsed by, or sponsored by BMW AG, BMW Group, MINI, Apple, or Homebridge.
'''
Path('README.md').write_text(readme)

Path('CHANGELOG.md').write_text(r'''# Changelog

## 0.1.0-beta.32

### Changed

- Final trustworthy telemetry beta before pausing active development.
- Kept the product surface focused on BMW Battery, BMW Windows, BMW Boot and BMW Tyres.
- Removed exposed HomeKit lock semantics from the accessory model.
- Removed command/control code paths from the client surface.
- Renamed the Homebridge display name to BM Home Stream.
- Rewrote README wording around BMW CarData telemetry limitations.

### Fixed

- Removed misleading HomeKit lock state when BMW does not publish trusted lock telemetry.
- Removed old command wording from runtime messages and documentation.

### Notes

BM Home Stream is intentionally telemetry-only.

BMW currently limits third-party integrations primarily to telemetry exposed through BMW CarData Stream. BM Home Stream does not attempt to bypass BMW platform restrictions.
''')

Path('.homebridge').mkdir(exist_ok=True)
Path('.homebridge/release-notes.md').write_text(r'''# BM Home Stream 0.1.0-beta.32

## Trustworthy telemetry beta

This release is the most conservative BM Home Stream beta so far. It focuses on the BMW CarData telemetry that has proved useful in Apple Home and removes misleading vehicle-control semantics.

## Apple Home tiles

- BMW Battery
- BMW Windows
- BMW Boot
- BMW Tyres

## Notes

BMW currently limits third-party integrations primarily to telemetry exposed through BMW CarData Stream.

BM Home Stream does not expose lock, unlock, climate or other vehicle command controls.
''')

pkg_path = Path('package.json')
pkg = json.loads(pkg_path.read_text())
pkg['version'] = '0.1.0-beta.32'
pkg['displayName'] = 'BM Home Stream'
pkg['description'] = 'BM Home Stream - BMW CarData telemetry for Apple Home via Homebridge'
pkg['homepage'] = 'https://bmhome.kernowekconsulting.co.uk'
pkg['repository'] = {'type': 'git', 'url': 'git+https://github.com/JayC68/bmhome.git'}
pkg['bugs'] = {'url': 'https://github.com/JayC68/bmhome/issues'}
pkg['keywords'] = ['homebridge-plugin','homebridge','bmhome','bmw','mini','apple-home','homekit','cardata','telemetry','ev','mqtt']
pkg['engines'] = {'node': '^22.0.0 || ^24.0.0', 'homebridge': '^1.8.0 || ^2.0.0'}
pkg_path.write_text(json.dumps(pkg, indent=2) + '\n')

print('Wrote BM Home Stream beta.32 files')
