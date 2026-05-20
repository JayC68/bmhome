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
      this.config.storagePath = this.api.user.storagePath();
      this.configValid = true;
      this.log.info(`BM Home Platform loaded - Name: ${this.config.name}`);
    } catch (err: any) {
      this.log.error(`BMHome config error: ${err.message}`);
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

    this.log.info('BM Home didFinishLaunching');

    const success = await this.client.initialize();

    if (!success) {
      this.log.error('Failed to initialize BMW Client. Check Client ID and BMW authorisation logs.');
      return;
    }

    const vehicleName = this.config.name || 'BM Home';
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
