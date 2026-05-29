from pathlib import Path
import json

Path("src/vehicleAccessory.ts").write_text("import { API, Logging, PlatformAccessory, Service } from 'homebridge';\nimport { BMWClient } from './bmwClient';\nimport { VehicleData } from './types';\n\nexport class VehicleAccessory {\n  private readonly log: Logging;\n  private readonly api: API;\n  private readonly client: BMWClient;\n  private readonly vin: string;\n  private readonly pollingInterval: number;\n\n  private batteryService!: Service;\n  private windowsService!: Service;\n  private bootService!: Service;\n  private tyresService!: Service;\n\n  constructor(\n    log: Logging,\n    api: API,\n    client: BMWClient,\n    vin: string,\n    name: string,\n    existingAccessory?: PlatformAccessory,\n  ) {\n    this.log = log;\n    this.api = api;\n    this.client = client;\n    this.vin = vin;\n    this.pollingInterval = (client.config?.pollingInterval ?? 180) * 1000;\n\n    let accessory: PlatformAccessory;\n\n    if (existingAccessory) {\n      accessory = existingAccessory;\n      this.log.info(`Restoring accessory from cache: ${name}`);\n    } else {\n      accessory = new api.platformAccessory(name, api.hap.uuid.generate(`bmhome-${vin || 'auto'}`));\n      api.registerPlatformAccessories('homebridge-bmhome', 'BMWHome', [accessory]);\n      this.log.info(`Registered new accessory: ${name}`);\n    }\n\n    accessory.getService(api.hap.Service.AccessoryInformation)!\n      .setCharacteristic(api.hap.Characteristic.Manufacturer, 'BMW Group')\n      .setCharacteristic(api.hap.Characteristic.Model, 'BMW CarData Stream')\n      .setCharacteristic(api.hap.Characteristic.SerialNumber, vin || 'auto');\n\n    this.batteryService =\n      accessory.getServiceById(api.hap.Service.Battery, 'battery') ??\n      accessory.getService(api.hap.Service.Battery) ??\n      accessory.addService(api.hap.Service.Battery, 'BMW Battery', 'battery');\n\n    this.windowsService =\n      accessory.getServiceById(api.hap.Service.ContactSensor, 'windows') ??\n      accessory.addService(api.hap.Service.ContactSensor, 'BMW Windows', 'windows');\n\n    this.bootService =\n      accessory.getServiceById(api.hap.Service.ContactSensor, 'boot') ??\n      accessory.addService(api.hap.Service.ContactSensor, 'BMW Boot', 'boot');\n\n    this.tyresService =\n      accessory.getServiceById(api.hap.Service.Switch, 'tyres') ??\n      accessory.addService(api.hap.Service.Switch, 'BMW Tyres', 'tyres');\n\n    this.setServiceName(this.batteryService, 'BMW Battery');\n    this.setServiceName(this.windowsService, 'BMW Windows');\n    this.setServiceName(this.bootService, 'BMW Boot');\n    this.setServiceName(this.tyresService, 'BMW Tyres');\n\n    this.fetchAndUpdate();\n    this.startPolling();\n  }\n\n  private setServiceName(service: Service, name: string): void {\n    const { Characteristic } = this.api.hap;\n    service.setCharacteristic(Characteristic.Name, name);\n    try {\n      service.setCharacteristic(Characteristic.ConfiguredName, name);\n    } catch {\n      // ConfiguredName is not available on every Homebridge/HAP version.\n    }\n  }\n\n  private async fetchAndUpdate(): Promise<void> {\n    try {\n      const data = await this.client.getVehicleData(this.vin);\n      if (data) {\n        this.updateCharacteristics(data);\n      }\n    } catch (err) {\n      this.log.error('Vehicle data fetch failed', err);\n    }\n  }\n\n  private startPolling(): void {\n    setInterval(() => this.fetchAndUpdate(), this.pollingInterval);\n  }\n\n  private updateContact(service: Service, isOpen?: boolean): void {\n    if (isOpen === undefined) {\n      return;\n    }\n\n    const { Characteristic } = this.api.hap;\n\n    service.updateCharacteristic(\n      Characteristic.ContactSensorState,\n      isOpen\n        ? Characteristic.ContactSensorState.CONTACT_NOT_DETECTED\n        : Characteristic.ContactSensorState.CONTACT_DETECTED,\n    );\n  }\n\n  private updateCharacteristics(data: VehicleData): void {\n    const { Characteristic } = this.api.hap;\n\n    if (data.soc !== undefined) {\n      this.batteryService.updateCharacteristic(Characteristic.BatteryLevel, data.soc);\n      this.batteryService.updateCharacteristic(\n        Characteristic.StatusLowBattery,\n        data.soc < 20\n          ? Characteristic.StatusLowBattery.BATTERY_LEVEL_LOW\n          : Characteristic.StatusLowBattery.BATTERY_LEVEL_NORMAL,\n      );\n    }\n\n    if (data.isCharging !== undefined || data.chargingStatus !== undefined) {\n      const status = String(data.chargingStatus || '').toLowerCase();\n      const isCharging = data.isCharging === true || status.includes('charging');\n\n      this.batteryService.updateCharacteristic(\n        Characteristic.ChargingState,\n        isCharging\n          ? Characteristic.ChargingState.CHARGING\n          : Characteristic.ChargingState.NOT_CHARGING,\n      );\n    }\n\n    this.updateContact(this.windowsService, data.windowsOpen);\n    this.updateContact(this.bootService, data.bootOpen);\n\n    if (data.tyresOk !== undefined) {\n      this.tyresService.updateCharacteristic(Characteristic.On, data.tyresOk);\n    }\n\n    this.log.debug(`Characteristics updated for VIN: ${data.vin ?? this.vin}`);\n  }\n}\n")

pkg_path = Path("package.json")
pkg = json.loads(pkg_path.read_text())
pkg["version"] = "0.1.0-beta.31"
pkg["displayName"] = "BM Home Stream"
pkg["description"] = "BM Home Stream - BMW CarData telemetry for Apple Home via Homebridge"
pkg["homepage"] = "https://bmhome.kernowekconsulting.co.uk"
pkg["repository"] = {"type": "git", "url": "git+https://github.com/JayC68/bmhome.git"}
pkg["bugs"] = {"url": "https://github.com/JayC68/bmhome/issues"}
pkg["keywords"] = ["homebridge-plugin","homebridge","bmhome","bmw","mini","apple-home","homekit","cardata","telemetry","ev","mqtt"]
pkg["engines"] = {"node": "^22.0.0 || ^24.0.0", "homebridge": "^1.8.0 || ^2.0.0"}
pkg_path.write_text(json.dumps(pkg, indent=2) + "\n")

readme = Path("README.md")
s = readme.read_text() if readme.exists() else "# BM Home Stream\n\n"
s = s.replace("BMHome", "BM Home Stream")
s = s.replace("BM Home StreamHome", "BM Home Stream")
s = s.replace("Your BMW, integrated into Apple Home.", "Your BMW telemetry, integrated into Apple Home.")
s = s.replace("Your BMW, integrated into Apple Home", "Your BMW telemetry, integrated into Apple Home")
s = s.replace("Fed by BMW’s CarData Stream.", "Fed by BMW’s CarData Stream.")
extra = """\n\n---\n\n## BMW CarData and Vehicle Control\n\nBM Home Stream is a telemetry-focused integration. It listens to BMW CarData Stream and displays the data BMW publishes.\n\nBMW currently limits third-party integrations primarily to telemetry exposed through BMW CarData Stream. BM Home Stream does not attempt to bypass BMW platform restrictions and does not expose lock, unlock, climate or other vehicle command controls.\n\nA misleading vehicle security tile is worse than no vehicle security tile. Lock status will only return if a reliable BMW CarData descriptor is proven across real vehicles.\n\n## Authorisation and Tokens\n\nBM Home Stream stores BMW CarData tokens locally and normally refreshes them automatically. Occasionally BMW may reject a stored refresh token, especially after a Homebridge restore, system rollback, account change, BMW backend change, or expired authorisation flow.\n\nWhen that happens BM Home Stream will show a new BMW authorisation link and one-time code in the Homebridge logs. Use the newest code shown. Older codes expire quickly and may be replaced if Homebridge restarts.\n\n## BMW Update Behaviour\n\nBMW CarData Stream is not a constant live telemetry feed. Updates may be delayed, may depend on the vehicle waking, and may not include every descriptor every time. BM Home Stream keeps listening and updates Apple Home when BMW publishes new data.\n"""
if "## BMW CarData and Vehicle Control" not in s:
    s = s.rstrip() + extra
readme.write_text(s)

Path(".homebridge").mkdir(exist_ok=True)
Path(".homebridge/release-notes.md").write_text("""# BM Home Stream 0.1.0-beta.31

## Telemetry-only release candidate

This release completes the shift from BMHome as a possible control surface to BM Home Stream as a monitoring integration for BMW CarData telemetry.

## Changed

- Display name changed to BM Home Stream.
- Removed the BMW Lock HomeKit tile.
- Removed active HomeKit lock semantics.
- Kept the Apple Home surface focused on Battery, Windows, Boot and Tyres.
- Clarified BMW CarData Stream limitations and token behaviour.

## Notes

BMW currently limits third-party integrations primarily to telemetry. BM Home Stream does not expose lock, unlock, climate or other vehicle command controls.
""")

Path("CHANGELOG.md").write_text("""# Changelog

## 0.1.0-beta.31

### Changed

- Renamed display name to BM Home Stream.
- Removed the BMW Lock tile and HomeKit lock semantics.
- Repositioned the plugin as telemetry-only monitoring for BMW CarData Stream.
- Kept Apple Home focused on Battery, Windows, Boot and Tyres.
- Updated documentation around BMW platform limitations, token refresh and event-driven updates.

### Fixed

- Removed misleading HomeKit lock state when BMW does not publish trusted lock telemetry.

## 0.1.0-beta.30

### Changed

- Repositioned BMHome as a telemetry-only BMW CarData integration for Apple Home.
- Updated documentation around BMW CarData Stream limitations.
""")

print("Wrote beta.31 full files")
