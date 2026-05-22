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
      .setCharacteristic(api.hap.Characteristic.Model, 'BMW Vehicle')
      .setCharacteristic(api.hap.Characteristic.SerialNumber, vin || 'auto');

    this.lockService =
      accessory.getService(api.hap.Service.LockMechanism) ??
      accessory.addService(api.hap.Service.LockMechanism, `${name} Door Lock`, 'lock');

    this.batteryService =
      accessory.getService(api.hap.Service.Battery) ??
      accessory.addService(api.hap.Service.Battery, `${name} Battery`, 'battery');

    this.heaterService =
      accessory.getService(api.hap.Service.HeaterCooler) ??
      accessory.addService(api.hap.Service.HeaterCooler, `${name} Preconditioning`, 'heat');

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

  private updateCharacteristics(data: VehicleData): void {
    const { Characteristic } = this.api.hap;

    if (data.lockStatus && data.lockStatus !== 'unknown') {
      const isLocked = data.lockStatus === 'locked';

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

    this.log.debug(`Characteristics updated for VIN: ${data.vin ?? this.vin}`);
  }
}
