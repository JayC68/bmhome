import axios from 'axios';
import * as mqtt from 'mqtt';
import * as fs from 'fs';
import * as path from 'path';
import * as crypto from 'crypto';
import { BMHomePlatformConfig, VehicleData, CommandResponse } from './types';

interface TokenStore {
  deviceCode?: string;
  userCode?: string;
  verificationUri?: string;
  verificationUriComplete?: string;
  accessToken?: string;
  refreshToken?: string;
  idToken?: string;
  gcid?: string;
  expiresAt?: number;
  codeVerifier?: string;
}

const DEVICE_CODE_URL = 'https://customer.bmwgroup.com/gcdm/oauth/device/code';
const TOKEN_URL = 'https://customer.bmwgroup.com/gcdm/oauth/token';
const MQTT_URL = 'mqtts://customer.streaming-cardata.bmwgroup.com:9000';
const SCOPE = 'authenticate_user openid cardata:streaming:read cardata:api:read';

export class BMWClient {
  public readonly config: BMHomePlatformConfig;
  private mqttClient?: mqtt.MqttClient;
  private tokenStore: TokenStore = {};
  private readonly tokenFile: string;
  private latestVehicleData: VehicleData | null = null;
  private mqttConnected = false;
  private lastMqttMessageAt?: Date;
  private lastMqttTopic?: string;

  constructor(config: BMHomePlatformConfig) {
    this.config = config;

    const storageRoot = config.storagePath || process.cwd();
    const bmhomeDir = path.join(storageRoot, 'bmhome');

    if (!fs.existsSync(bmhomeDir)) {
      fs.mkdirSync(bmhomeDir, { recursive: true });
    }

    this.tokenFile = path.join(bmhomeDir, 'cardata-token-store.json');
    this.loadTokenStore();
  }

  async initialize(): Promise<boolean> {
    console.log(`[BMWClient] Initializing BMHome CarData client for clientId: ${this.safeClientId()}`);

    try {
      await this.ensureAuthenticated();

      if (this.config.enableStreaming !== false) {
        await this.connectMqtt();
      }

      return true;
    } catch (err: any) {
      console.error(`[BMWClient] Initialization failed: ${err?.message || err}`);
      this.logAxiosError(err, 'initialize');
      return false;
    }
  }

  async getVehicleData(vin?: string): Promise<VehicleData | null> {
    const requestedVin = vin || this.config.vin || this.latestVehicleData?.vin || '';

    if (this.latestVehicleData) {
      if (!requestedVin || this.latestVehicleData.vin === requestedVin) {
        return this.latestVehicleData;
      }
    }

    if (this.mqttConnected) {
      console.warn('[BMWClient] MQTT connected but no live BMW CarData payload received yet.');
    } else {
      console.warn('[BMWClient] MQTT not connected yet.');
    }

    return null;
  }

  async lock(vin: string): Promise<CommandResponse> {
    return {
      success: false,
      message: `Lock command is not implemented in BMHome yet. CarData listening is active; command/control research is pending for VIN ${vin || 'unknown'}.`,
      command: 'lock',
    };
  }

  async unlock(vin: string): Promise<CommandResponse> {
    return {
      success: false,
      message: `Unlock command is not implemented in BMHome yet. CarData listening is active; command/control research is pending for VIN ${vin || 'unknown'}.`,
      command: 'unlock',
    };
  }

  async precondition(vin: string, activate: boolean): Promise<CommandResponse> {
    return {
      success: false,
      message: `Preconditioning ${activate ? 'start' : 'stop'} is not implemented in BMHome yet. CarData is read/listen first.`,
      command: 'precondition',
    };
  }

  async startPreconditioning(vin: string): Promise<CommandResponse> {
    return this.precondition(vin, true);
  }

  async stopPreconditioning(vin: string): Promise<CommandResponse> {
    return this.precondition(vin, false);
  }

  destroy(): void {
    if (this.mqttClient) {
      this.mqttClient.end(true);
      this.mqttClient = undefined;
    }
  }

  private async ensureAuthenticated(): Promise<void> {
    if (this.hasUsableTokens()) {
      return;
    }

    if (this.tokenStore.refreshToken) {
      try {
        await this.refreshTokens();
        if (this.hasUsableTokens()) {
          return;
        }
      } catch (err: any) {
        console.warn(`[BMWClient] Token refresh failed: ${err?.message || err}`);
      }
    }

    if (this.tokenStore.deviceCode && this.tokenStore.codeVerifier) {
      try {
        await this.exchangeDeviceCode();
        if (this.hasUsableTokens()) {
          return;
        }
      } catch (err: any) {
        console.warn(`[BMWClient] Device-code token exchange not ready or failed: ${err?.message || err}`);
      }
    }

    await this.startDeviceFlow();
    throw new Error('BMW authorisation required. Check Homebridge logs for the BMW verification URL and user code, complete authorisation, then restart BMHome.');
  }

  private async startDeviceFlow(): Promise<void> {
    const verifier = this.base64Url(crypto.randomBytes(32));
    const challenge = this.base64Url(crypto.createHash('sha256').update(verifier).digest());

    const params = new URLSearchParams();
    params.set('client_id', this.config.clientId);
    params.set('scope', SCOPE);
    params.set('code_challenge', challenge);
    params.set('code_challenge_method', 'S256');

    const response = await axios.post(DEVICE_CODE_URL, params, {
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      timeout: 30000,
    });

    this.tokenStore.deviceCode = response.data.device_code;
    this.tokenStore.userCode = response.data.user_code;
    this.tokenStore.verificationUri = response.data.verification_uri;
    this.tokenStore.verificationUriComplete = response.data.verification_uri_complete;
    this.tokenStore.codeVerifier = verifier;
    this.saveTokenStore();

    console.warn('============================================================');
    console.warn('[BMWClient] BMW CarData authorisation required');
    console.warn(`[BMWClient] Open: ${this.tokenStore.verificationUriComplete || this.tokenStore.verificationUri}`);
    console.warn(`[BMWClient] Code: ${this.tokenStore.userCode}`);
    console.warn('[BMWClient] After approving access, restart Homebridge/BMHome.');
    console.warn('============================================================');
  }

  private async exchangeDeviceCode(): Promise<void> {
    if (!this.tokenStore.deviceCode || !this.tokenStore.codeVerifier) {
      throw new Error('No device code flow in progress');
    }

    const params = new URLSearchParams();
    params.set('grant_type', 'urn:ietf:params:oauth:grant-type:device_code');
    params.set('client_id', this.config.clientId);
    params.set('device_code', this.tokenStore.deviceCode);
    params.set('code_verifier', this.tokenStore.codeVerifier);

    const response = await axios.post(TOKEN_URL, params, {
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      timeout: 30000,
    });

    this.applyTokenResponse(response.data);
  }

  private async refreshTokens(): Promise<void> {
    if (!this.tokenStore.refreshToken) {
      throw new Error('No refresh token available');
    }

    const params = new URLSearchParams();
    params.set('grant_type', 'refresh_token');
    params.set('client_id', this.config.clientId);
    params.set('refresh_token', this.tokenStore.refreshToken);

    const response = await axios.post(TOKEN_URL, params, {
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      timeout: 30000,
    });

    this.applyTokenResponse(response.data);
  }

  private async connectMqtt(): Promise<void> {
    if (!this.tokenStore.idToken || !this.tokenStore.gcid) {
      console.warn('[BMWClient] MQTT not started because id_token/gcid are not available yet.');
      return;
    }

    const vinTopic = this.config.vin || '+';

    console.log(`[BMWClient] Preparing MQTT connection`);
    console.log(`[BMWClient] VIN topic (BMW portal topic): ${vinTopic}`);
    console.log(`[BMWClient] MQTT password source: ${this.tokenStore.accessToken ? 'accessToken' : 'idToken fallback'}`);

    this.mqttClient = mqtt.connect(MQTT_URL, {
      username: this.tokenStore.gcid,
      password: this.tokenStore.accessToken || this.tokenStore.idToken,
      keepalive: 30,
      reconnectPeriod: 30000,
      clean: true,
    });

    this.mqttClient.on('connect', () => {
      this.mqttConnected = true;

      console.log('[BMWClient] MQTT connected');

      const topics = [vinTopic];

      topics.forEach((topic) => {
        console.log(`[BMWClient] Subscribing to BMW portal topic: ${topic}`);

        this.mqttClient?.subscribe(topic, (err, granted) => {
          if (err) {
            console.error(`[BMWClient] MQTT subscribe failed for ${topic}: ${err.message}`);
          } else {
            console.log(`[BMWClient] MQTT subscribe success for ${topic}`);
            console.log(`[BMWClient] MQTT granted: ${JSON.stringify(granted)}`);
          }
        });
      });
    });

    this.mqttClient.on('message', (receivedTopic, payload) => {
      console.log('[BMWClient] MQTT RAW PAYLOAD START');
      console.log(`[BMWClient] MQTT message received on topic: ${receivedTopic}`);
      console.log(`[BMWClient] MQTT payload size: ${payload.length} bytes`);
      try {
        const raw = payload.toString();
        console.log(`[BMWClient] MQTT payload preview: ${raw.slice(0, 4000)}`);
        const parsed = JSON.parse(raw);
        console.log(`[BMWClient] MQTT parsed top-level keys: ${Object.keys(parsed).join(', ')}`);
      } catch (err: any) {
        console.error(`[BMWClient] MQTT payload parse diagnostic failed: ${err?.message || err}`);
      }
      console.log('[BMWClient] MQTT RAW PAYLOAD END');

      this.lastMqttMessageAt = new Date();
      this.lastMqttTopic = receivedTopic;

      this.handleMqttMessage(receivedTopic, payload);
    });

    this.mqttClient.on('error', (err) => {
      console.error(`[BMWClient] MQTT error: ${err.message}`);
    });

    this.mqttClient.on('close', () => {
      this.mqttConnected = false;
      console.warn('[BMWClient] MQTT connection closed');
    });

    this.mqttClient.on('reconnect', () => {
      console.warn('[BMWClient] MQTT reconnecting...');
    });

    this.mqttClient.on('offline', () => {
      console.warn('[BMWClient] MQTT offline');
    });
  }

  private handleMqttMessage(topic: string, payload: Buffer): void {
    try {
      const text = payload.toString('utf8');
      const json = JSON.parse(text);
      const vin = this.extractVin(topic, json);

      const data: VehicleData = {
        vin,
        soc: this.findNumber(json, ['soc', 'stateOfCharge', 'chargingLevelHv', 'batteryLevel']),
        remainingRange: this.findNumber(json, ['remainingRange', 'range', 'electricRange', 'rangeElectric']),
        isCharging: this.findBoolean(json, ['isCharging', 'chargingActive']),
        chargingStatus: this.findString(json, ['chargingStatus', 'chargingState']),
        lockStatus: this.normaliseLockStatus(this.findString(json, ['lockStatus', 'doorLockState', 'centralLockState'])),
        preconditionActive: this.findBoolean(json, ['preconditionActive', 'climateActive', 'preconditioningActive']),
        raw: json,
        timestamp: new Date(),
      };

      this.latestVehicleData = data;

      console.log(`[BMWClient] MQTT vehicle update received for ${vin}`);

      console.log(
        `[BMWClient] Parsed vehicle state: ` +
        `SOC=${data.soc ?? 'unknown'} ` +
        `Range=${data.remainingRange ?? 'unknown'} ` +
        `Charging=${data.isCharging ?? 'unknown'} ` +
        `Lock=${data.lockStatus ?? 'unknown'}`
      );
    } catch (err: any) {
      console.error(`[BMWClient] Failed to parse MQTT payload: ${err?.message || err}`);
    }
  }

  private extractVin(topic: string, payload: any): string {
    if (typeof payload?.vin === 'string') {
      return payload.vin;
    }

    const parts = topic.split('/');
    const possibleVin = parts[parts.length - 1];

    return possibleVin || this.config.vin || 'unknown';
  }

  private applyTokenResponse(data: any): void {
    this.tokenStore.accessToken = data.access_token;
    this.tokenStore.refreshToken = data.refresh_token || this.tokenStore.refreshToken;
    this.tokenStore.idToken = data.id_token;
    this.tokenStore.expiresAt = Date.now() + ((data.expires_in || 3600) * 1000) - 60000;

    const decoded = this.decodeJwt(data.id_token);
    this.tokenStore.gcid =
      decoded?.gcid ||
      decoded?.sub ||
      decoded?.['https://customer.bmwgroup.com/gcid'] ||
      this.tokenStore.gcid;

    this.saveTokenStore();
  }

  private hasUsableTokens(): boolean {
    return Boolean(
      this.tokenStore.accessToken &&
      this.tokenStore.idToken &&
      this.tokenStore.expiresAt &&
      this.tokenStore.expiresAt > Date.now() + 60000,
    );
  }

  private loadTokenStore(): void {
    try {
      if (fs.existsSync(this.tokenFile)) {
        this.tokenStore = JSON.parse(fs.readFileSync(this.tokenFile, 'utf8'));
      }
    } catch (err: any) {
      console.warn(`[BMWClient] Could not read token store: ${err?.message || err}`);
      this.tokenStore = {};
    }
  }

  private saveTokenStore(): void {
    fs.writeFileSync(this.tokenFile, JSON.stringify(this.tokenStore, null, 2));
    try {
      fs.chmodSync(this.tokenFile, 0o600);
    } catch {
      // Best effort only.
    }
  }

  private decodeJwt(token?: string): any {
    if (!token) {
      return null;
    }

    try {
      const [, payload] = token.split('.');
      return JSON.parse(Buffer.from(payload, 'base64url').toString('utf8'));
    } catch {
      return null;
    }
  }

  private findNumber(obj: any, keys: string[]): number | undefined {
    const value = this.findValue(obj, keys);
    const numberValue = Number(value);
    return Number.isFinite(numberValue) ? numberValue : undefined;
  }

  private findString(obj: any, keys: string[]): string | undefined {
    const value = this.findValue(obj, keys);
    return typeof value === 'string' ? value : undefined;
  }

  private findBoolean(obj: any, keys: string[]): boolean | undefined {
    const value = this.findValue(obj, keys);

    if (typeof value === 'boolean') {
      return value;
    }

    if (typeof value === 'string') {
      const lower = value.toLowerCase();
      if (['true', 'active', 'charging', 'on', 'yes'].includes(lower)) {
        return true;
      }
      if (['false', 'inactive', 'not_charging', 'off', 'no'].includes(lower)) {
        return false;
      }
    }

    return undefined;
  }

  private findValue(obj: any, keys: string[]): unknown {
    if (!obj || typeof obj !== 'object') {
      return undefined;
    }

    for (const key of keys) {
      if (Object.prototype.hasOwnProperty.call(obj, key)) {
        return obj[key];
      }
    }

    for (const value of Object.values(obj)) {
      if (value && typeof value === 'object') {
        const nested = this.findValue(value, keys);
        if (nested !== undefined) {
          return nested;
        }
      }
    }

    return undefined;
  }

  private normaliseLockStatus(value?: string): 'locked' | 'unlocked' | 'unknown' {
    if (!value) {
      return 'unknown';
    }

    const lower = value.toLowerCase();

    if (lower.includes('unlock') || lower === 'open') {
      return 'unlocked';
    }

    if (lower.includes('lock') || lower === 'closed' || lower === 'secure') {
      return 'locked';
    }

    return 'unknown';
  }

  private logAxiosError(err: any, context: string): void {
    if (!err?.response) {
      return;
    }

    const status = err.response.status;
    const data = err.response.data;

    console.error(`[BMWClient] BMW API error during ${context}: HTTP ${status}`);

    if (data) {
      try {
        console.error(`[BMWClient] BMW API response: ${JSON.stringify(data)}`);
      } catch {
        console.error(`[BMWClient] BMW API response could not be stringified`);
      }
    }
  }

  private base64Url(buffer: Buffer): string {
    return buffer.toString('base64url');
  }

  private safeClientId(): string {
    return this.config.clientId ? `${this.config.clientId.substring(0, 8)}...` : 'missing';
  }
}
