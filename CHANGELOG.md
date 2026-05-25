# Changelog

## 0.1.0-beta.29

### Changed

- Removed the legacy BMW Preconditioning tile.
- Simplified the Apple Home layout to focus on proven useful tiles.
- Refreshed README for public beta users.
- Updated package metadata for Homebridge 2.x compatibility.
- Improved consumer-facing wording around BMW CarData Stream behaviour.

### Fixed

- Removed unimplemented HeaterCooler / climate placeholder service.
- Reduced risk of confusing unsupported controls in Apple Home.
- Kept quiet MQTT reconnect/logging behaviour.

### Notes

BMHome currently focuses on presenting BMW CarData Stream telemetry in Apple Home.

Remote lock/unlock and climate commands remain under research and are not currently implemented as reliable user-facing features.

---

## 0.1.0-beta.28

### Changed

- Removed the standalone BMW Doors tile from the HomeKit surface.
- Kept Windows and Boot as more useful physical-state sensors.

## 0.1.0-beta.27

### Changed

- Added human-readable HomeKit service names.
- Improved Apple Home tile clarity.

## 0.1.0-beta.26

### Fixed

- Fixed cached HomeKit service restoration using stable service subtypes.

## 0.1.0-beta.25

### Added

- Added last-known vehicle state persistence.

## 0.1.0-beta.24

### Added

- Added HomeKit services for Battery, Windows, Boot and Tyres.
- Added tyre OK summary state.

## 0.1.0-beta.22

### Added

- Confirmed and finalised BMW state-of-charge parsing via `vehicle.drivetrain.batteryManagement.header`.
