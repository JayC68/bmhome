export interface BMHomePlatformConfig {
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
  remainingRange?: number;
  isCharging?: boolean;
  chargingStatus?: string;
  lockStatus?: 'locked' | 'unlocked' | 'unknown';
  preconditionActive?: boolean;
  doorsOpen?: boolean;
  windowsOpen?: boolean;
  alarmActive?: boolean;
  tyrePressures?: number[];
  raw?: unknown;
  rawDescriptors?: Record<string, unknown>;
  timestamp: Date;
}

export interface CommandResponse {
  success: boolean;
  message: string;
  command: string;
}
