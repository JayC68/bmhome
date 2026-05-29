# BM Home Stream

**Your BMW telemetry, integrated into Apple Home.**

Fed by BMW’s CarData Stream.

BM Home Stream is a Homebridge plugin that brings selected BMW vehicle telemetry into Apple Home, so your car can sit alongside the rest of your HomeKit devices.

BM Home Stream is currently in public beta.

---

## What BM Home Stream Shows in Apple Home

BM Home Stream is designed to present useful BMW telemetry as simple Apple Home tiles:

- **BMW Battery** — battery state of charge when BMW publishes it
- **BMW Windows** — open / closed window status
- **BMW Boot** — boot / trunk open status
- **BMW Tyres** — simple OK / not OK tyre pressure status

BM Home Stream deliberately avoids cluttering Apple Home with raw technical telemetry.

---

## What BM Home Stream Is

BM Home Stream is a telemetry integration.

It listens to BMW CarData Stream and displays the data BMW publishes. It does not try to bypass BMW platform restrictions, and it does not pretend to provide vehicle control where BMW has not made that available to third-party integrations.

---

## Current Limitations

BMW currently limits third-party integrations primarily to telemetry exposed through BMW CarData Stream. BM Home Stream can only show the state BMW publishes.

- BMW CarData Stream is event-driven and can be delayed
- some descriptors may not be emitted by BMW for every vehicle
- the vehicle may stop publishing while asleep
- values may be stale until BMW emits a fresh event
- battery state of charge may be intermittent depending on descriptor availability
- lock/unlock, climate and other vehicle commands are not exposed by BM Home Stream

BM Home Stream only displays data BMW makes available through CarData Stream.

---

## Why BM Home Stream Does Not Lock or Unlock the Car

BMW CarData Stream is a telemetry-focused platform. Modern third-party CarData access provides vehicle data, but does not provide reliable third-party vehicle command support.

BMW’s own services can also report that vehicle status is temporarily unknown. For example, BMW may reject a lock or unlock action if door status is unknown to BMW’s backend.

BM Home Stream therefore does not expose a lock/unlock tile. A wrong lock state is worse than no lock state.

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
```

---

## Authorisation and Tokens

BM Home Stream stores BMW CarData tokens locally and normally refreshes them automatically.

Occasionally BMW may reject a stored refresh token. This can happen after a Homebridge restore, system rollback, account change, BMW backend change, or an expired authorisation flow.

When that happens BM Home Stream will show a new BMW authorisation link and one-time code in the Homebridge logs. Use the newest code shown.

---

## BMW Update Behaviour

BMW CarData Stream is not a constant live telemetry feed. Updates may be delayed, may depend on the vehicle waking, and may not include every descriptor every time.

BM Home Stream keeps the last known state locally so Apple Home can remain useful even when BMW is quiet.

---

## Disclaimer

BM Home Stream is an independent Homebridge plugin.

It is not affiliated with, endorsed by, or sponsored by BMW AG, BMW Group, MINI, Apple, or Homebridge.
