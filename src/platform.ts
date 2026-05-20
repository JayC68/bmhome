import { API, DynamicPlatformPlugin, Logging, PlatformAccessory, PlatformConfig } from 'homebridge';
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
      this.configValid = true;
      this.log.info(`BMW Home Platform loaded - Name: ${this.config.name}`);
    } catch (err: any) {
      this.log.error(`BMWHome config error: ${err.message}`);
      this.log.error('Plugin will not initialise until the config is corrected in the Homebridge UI.');
      return; // never throw from a Homebridge constructor
    }

    this.client = new BMWClient(this.config);

    api.on('didFinishLaunching', async () => {
      await this.onDidFinishLaunching();
    });
  }

  async onDidFinishLaunching() {
    if (!this.configValid) {
      this.log.error('Skipping launch — invalid config.');
      return;
    }

    this.log.info('🚗 BMW Home didFinishLaunching');

    const success = await this.client.initialize();
    if (!success) {
      this.log.error('Failed to initialize BMW Client — check your Client ID.');
      return;
    }

    const vehicleName = this.config.name || 'BMW Home';
    const vin = this.config.vin || '';
    const uuid = this.api.hap.uuid.generate(`bmhome-${vin}`);
    const existingAccessory = this.accessories.find(a => a.UUID === uuid);

    if (existingAccessory) {
      this.log.info(`Restoring cached accessory: ${existingAccessory.displayName}`);
      new VehicleAccessory(this.log, this.api, this.client, vin, vehicleName, existingAccessory);
    } else {
      this.log.info(`Registering new accessory: ${vehicleName}`);
      new VehicleAccessory(this.log, this.api, this.client, vin, vehicleName);
    }
  }

  configureAccessory(accessory: PlatformAccessory) {
    this.log.info(`Loading cached accessory: ${accessory.displayName}`);
    this.accessories.push(accessory);
  }
}
