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
  rawSoc?: number;
  remainingRange?: number;
  remainingRangeKm?: number;
  remainingRangeMiles?: number;
  distanceUnit?: 'mi' | 'km';
  isCharging?: boolean;
  pluggedIn?: boolean;
  chargingPortStatus?: string;
  chargingPower?: number;
  chargingStatus?: string;
  doorsOpen?: boolean;
  windowsOpen?: boolean;
  bootOpen?: boolean;
  tyrePressures?: number[];
  tyresOk?: boolean;
  vehicleBrand?: 'BMW' | 'MINI';
  remainingFuel?: number;
  rawDescriptors?: unknown;
  restoredFromCache?: boolean;
  cachedAt?: string;
  raw?: unknown;
  timestamp: Date;
}
