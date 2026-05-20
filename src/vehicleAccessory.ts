import { AccessoryPlugin, API, Logging, Service, Characteristic } from 'homebridge';
import { BMWClient } from './bmwClient';
import { VehicleData } from './types';

export class VehicleAccessory {
  private readonly log: Logging;
  private readonly api: API;
  private readonly client: BMWClient;
  private readonly vin: string;

  private lockService: Service;
  private batteryService: Service;
  private heaterService: Service;

  constructor(log: Logging, api: API, client: BMWClient, vin: string, name: string) {
    this.log = log;
    this.api = api;
    this.client = client;
    this.vin = vin;

    const accessory = new api.platformAccessory(name, api.hap.uuid.generate(`bmhome-${vin}`));

    // Lock Service
    this.lockService = accessory.addService(api.hap.Service.LockMechanism, `${name} Door Lock`, 'lock');
    
    // Battery Service
    this.batteryService = accessory.addService(api.hap.Service.Battery, `${name} Battery`, 'battery');

    // Heater / Preconditioning
    this.heaterService = accessory.addService(api.hap.Service.HeaterCooler, `${name} Preconditioning`, 'heat');

    // Register the accessory
    api.registerPlatformAccessories('homebridge-bmhome', 'BMWHome', [accessory]);

    this.setupHandlers();
    this.startPolling();
  }

  private setupHandlers() {
    // Lock Target State
    this.lockService.getCharacteristic(this.api.hap.Characteristic.LockTargetState)
      .onSet(async (value) => {
        try {
          const command = value === this.api.hap.Characteristic.LockTargetState.SECURED 
            ? await this.client.lock(this.vin) 
            : await this.client.unlock(this.vin);
          
          this.log.info(`Command result: ${command.message}`);
        } catch (err) {
          this.log.error("Lock command failed", err);
        }
      });
  }

  private async startPolling() {
    setInterval(async () => {
      const data = await this.client.getVehicleData(this.vin);
      if (data) this.updateCharacteristics(data);
    }, 180000); // every 3 minutes
  }

  private updateCharacteristics(data: VehicleData) {
    // Update Lock
    const currentLock = data.lockStatus === 'locked' 
      ? this.api.hap.Characteristic.LockCurrentState.SECURED 
      : this.api.hap.Characteristic.LockCurrentState.UNSECURED;

    this.lockService.updateCharacteristic(this.api.hap.Characteristic.LockCurrentState, currentLock);

    // Update Battery
    if (data.soc !== undefined) {
      this.batteryService.updateCharacteristic(this.api.hap.Characteristic.BatteryLevel, data.soc);
    }

    this.log.debug(`Updated characteristics for ${data.vin}`);
  }
}
