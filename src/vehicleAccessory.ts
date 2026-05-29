import { API, Logging, PlatformAccessory, Service } from 'homebridge';
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
    try {
      service.setCharacteristic(Characteristic.ConfiguredName, name);
    } catch {
      // ConfiguredName is not available on every Homebridge/HAP version.
    }
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

  private updateContact(service: Service, isOpen?: boolean): void {
    if (isOpen === undefined) {
      return;
    }

    const { Characteristic } = this.api.hap;

    service.updateCharacteristic(
      Characteristic.ContactSensorState,
      isOpen
        ? Characteristic.ContactSensorState.CONTACT_NOT_DETECTED
        : Characteristic.ContactSensorState.CONTACT_DETECTED,
    );
  }

  private updateCharacteristics(data: VehicleData): void {
    const { Characteristic } = this.api.hap;

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

    this.updateContact(this.windowsService, data.windowsOpen);
    this.updateContact(this.bootService, data.bootOpen);

    if (data.tyresOk !== undefined) {
      this.tyresService.updateCharacteristic(Characteristic.On, data.tyresOk);
    }

    this.log.debug(`Characteristics updated for VIN: ${data.vin ?? this.vin}`);
  }
}
