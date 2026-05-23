export interface BMHomePlatformConfig {
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
  remainingRange?: number;
  isCharging?: boolean;
  chargingStatus?: string;
  lockStatus?: 'locked' | 'unlocked' | 'unknown';
  preconditionActive?: boolean;
  raw?: unknown;
  timestamp: Date;
}

export interface CommandResponse {
  success: boolean;
  message: string;
  command: string;
}
