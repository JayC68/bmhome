export interface BMHomePlatformConfig {
  name?: string;
  clientId: string;           // required
  vin?: string;
  enableStreaming?: boolean;
  pollingInterval?: number;
}

export interface VehicleData {
  vin: string;
  soc?: number;                    // State of Charge %
  remainingRange?: number;         // km
  isCharging?: boolean;
  lockStatus?: 'locked' | 'unlocked';
  preconditionActive?: boolean;
  timestamp: Date;
}

export interface CommandResponse {
  success: boolean;
  message: string;
  command?: string;
}
