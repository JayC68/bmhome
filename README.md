# BM Home Stream

**Your BMW telemetry, integrated into Apple Home.**

Fed by BMW’s CarData Stream.

BM Home Stream is a Homebridge plugin that brings selected BMW vehicle information into Apple Home, so your car can sit alongside the rest of your HomeKit devices.

BM Home Stream is currently in public beta.

---

## What BM Home Stream Shows in Apple Home

BM Home Stream is designed to present useful BMW information as simple Apple Home tiles:

- **BMW Battery** — battery state of charge when BMW publishes it
- **BMW Lock** — vehicle security tile, with state feedback where BMW provides it
- **BMW Windows** — open / closed window status
- **BMW Boot** — boot / trunk open status
- **BMW Tyres** — simple OK / not OK tyre pressure status

BM Home Stream deliberately avoids cluttering Apple Home with raw technical telemetry.

---

## How BM Home Stream Works

BM Home Stream connects to **BMW CarData Stream**.

BMW decides what data is published, when it is published, and which descriptors are available for each vehicle. BM Home Stream displays the information BMW sends.

This means BM Home Stream may not always match the MyBMW app instantly. Some updates arrive after vehicle activity such as driving, charging, locking, unlocking, or a BMW backend refresh.

---

## What Works Today

Validated during BM Home Stream beta testing:

- BMW CarData Stream MQTT connection
- BMW iX3 battery state of charge
- Remaining range
- Window / boot descriptor parsing
- Tyre pressure summary
- Apple Home child bridge
- Human-readable Apple Home tile names
- Last-known vehicle state caching
- Quiet reconnect/logging behaviour

---

## Current Limitations

BM Home Stream is not a replacement for the MyBMW app.

Current limitations:

- BMW CarData Stream is event-driven and can be delayed
- Some selected descriptors may not be emitted by BMW for every vehicle
- 
- Charging state and charging power may not be published reliably
- MINI support is expected through BMW Group CarData but is not yet widely field-tested

BM Home Stream only displays or acts on data BMW makes available through CarData Stream.

---

## BMW CarData Stream Setup

Sign in to BMW CarData using the same BMW ID used in the MyBMW app.

BMW UK CarData catalogue:

```text
https://www.bmw.co.uk/en-gb/mybmw/public/cardata-telematic-catalogue
```

Navigate to:

```text
Login
→ My Vehicle Overview
→ BMW CarData
→ CarData API
→ CarData Stream
```

Create or confirm your CarData client, then enable and save the descriptors BM Home Stream needs.

### Recommended Descriptors

```text
vehicle.drivetrain.batteryManagement.header
vehicle.drivetrain.electricEngine.kombiRemainingElectricRange
vehicle.drivetrain.lastRemainingRange

vehicle.body.trunk.isOpen
vehicle.body.trunk.door.isOpen

vehicle.cabin.window.row1.driver.status
vehicle.cabin.window.row1.passenger.status
vehicle.cabin.window.row2.driver.status
vehicle.cabin.window.row2.passenger.status
vehicle.cabin.sunroof.status

vehicle.chassis.axle.row1.wheel.left.tire.pressure
vehicle.chassis.axle.row1.wheel.right.tire.pressure
vehicle.chassis.axle.row2.wheel.left.tire.pressure
vehicle.chassis.axle.row2.wheel.right.tire.pressure

vehicle.body.chargingPort.status
vehicle.powertrain.electric.battery.charging.power
```

### Optional / Model-Specific Descriptors

```text
vehicle.trip.segment.end.drivetrain.batteryManagement.hvSoc
vehicle.drivetrain.fuelSystem.remainingFuel
vehicle.cabin.convertible.roofRetractableStatus
vehicle.vehicle.antiTheftAlarmSystem.alarm.isOn
```

Not every descriptor is available on every vehicle.

---

## Homebridge Setup

Install BM Home Stream through Homebridge.

Plugin settings require:

- BMW CarData Client ID
- VIN
- BMW account authentication
- distance unit preference

BM Home Stream should be run as a child bridge.

After configuration, pair the BM Home Stream bridge with Apple Home using the QR code shown in Homebridge.

---

## BMW Update Behaviour

BMW vehicles do not continuously publish all telemetry in real time.

Updates may appear:

- after driving
- after charging
- after lock or unlock events
- after the vehicle wakes
- after BMW backend refreshes

BM Home Stream keeps the last known state locally so Apple Home can remain useful even when BMW is quiet.

---

## Support Status

BM Home Stream is under active development.

The current beta is intended for technically comfortable BMW owners who understand that BMW CarData behaviour varies by vehicle, region and backend support.

Feedback and issue reports are welcome on GitHub.

---

## Disclaimer

BM Home Stream is an independent Homebridge plugin.

It is not affiliated with, endorsed by, or sponsored by BMW AG, BMW Group, MINI, Apple, or Homebridge.

---

## BMW CarData Limitations

BM Home Stream uses BMW CarData Stream, which is currently a telemetry-focused platform.

BMW presently restricts most third-party command and remote-control functionality, including vehicle lock/unlock operations.

Because BM Home Stream only exposes data BMW publishes through CarData Stream:

- some values may be delayed
- some values may disappear temporarily
- some descriptors may not exist for all vehicles
- updates may pause while the vehicle sleeps
- telemetry availability varies by region, firmware and vehicle model

Current BM Home Stream focus areas:

- EV range visibility
- battery telemetry (when available)
- window-open awareness
- boot/tailgate state
- tyre status visibility
- lightweight Apple Home presence

BM Home Stream does not attempt to bypass BMW platform restrictions.

---

## BMW CarData and Vehicle Control

BM Home Stream is a telemetry-focused integration. It listens to BMW CarData Stream and displays the data BMW publishes.

BMW currently limits third-party integrations primarily to telemetry exposed through BMW CarData Stream. BM Home Stream does not attempt to bypass BMW platform restrictions and does not expose lock, unlock, climate or other vehicle command controls.

A misleading vehicle security tile is worse than no vehicle security tile. Lock status will only return if a reliable BMW CarData descriptor is proven across real vehicles.

## Authorisation and Tokens

BM Home Stream stores BMW CarData tokens locally and normally refreshes them automatically. Occasionally BMW may reject a stored refresh token, especially after a Homebridge restore, system rollback, account change, BMW backend change, or expired authorisation flow.

When that happens BM Home Stream will show a new BMW authorisation link and one-time code in the Homebridge logs. Use the newest code shown. Older codes expire quickly and may be replaced if Homebridge restarts.

## BMW Update Behaviour

BMW CarData Stream is not a constant live telemetry feed. Updates may be delayed, may depend on the vehicle waking, and may not include every descriptor every time. BM Home Stream keeps listening and updates Apple Home when BMW publishes new data.
