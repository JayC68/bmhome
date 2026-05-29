# Changelog

## 0.1.0-beta.32

### Changed

- Final trustworthy telemetry beta before pausing active development.
- Kept the product surface focused on BMW Battery, BMW Windows, BMW Boot and BMW Tyres.
- Removed exposed HomeKit lock semantics from the accessory model.
- Removed command/control code paths from the client surface.
- Renamed the Homebridge display name to BM Home Stream.
- Rewrote README wording around BMW CarData telemetry limitations.

### Fixed

- Removed misleading HomeKit lock state when BMW does not publish trusted lock telemetry.
- Removed old command wording from runtime messages and documentation.

### Notes

BM Home Stream is intentionally telemetry-only.

BMW currently limits third-party integrations primarily to telemetry exposed through BMW CarData Stream. BM Home Stream does not attempt to bypass BMW platform restrictions.
