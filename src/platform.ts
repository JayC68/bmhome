import { API, DynamicPlatformPlugin, Logging, PlatformAccessory, PlatformConfig } from 'homebridge';
import { BMHomePlatformConfig } from './types';
import { BMWClient } from './bmwClient';
import { VehicleAccessory } from './vehicleAccessory';
import { validateConfig } from './configValidator';

export class BMWHomePlatform implements DynamicPlatformPlugin {
  private readonly log: Logging;
  private readonly api: API;
  private readonly config: BMHomePlatformConfig;
  private readonly accessories: PlatformAccessory[] = [];
  private client!: BMWClient;

  constructor(log: Logging, config: PlatformConfig, api: API) {
    this.log = log;
    this.api = api;

    try {
      this.config = validateConfig(config);
      this.log.info(`BMW Home Platform loaded - Name: ${this.config.name}`);
    } catch (err: any) {
      this.log.error(err.message);
      throw err;
    }

    this.client = new BMWClient(this.config);

    api.on('didFinishLaunching', async () => {
      await this.onDidFinishLaunching();
    });
  }

  async onDidFinishLaunching() {
    this.log.info('🚗 BMW Home didFinishLaunching');

    const success = await this.client.initialize();
    if (!success) {
      this.log.error("Failed to initialize BMW Client");
      return;
    }

    const vehicleName = this.config.name || "BMW Home";
    new VehicleAccessory(this.log, this.api, this.client, this.config.vin || "", vehicleName);
  }

  configureAccessory(accessory: PlatformAccessory) {
    this.accessories.push(accessory);
  }
}
