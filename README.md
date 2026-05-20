# 1. Create the file first
cat > README.md << 'EOF'
# BMHome - BMW in Apple Home

**Local. Stable. Native HomeKit control for your BMW.**

Control your BMW directly from Apple Home:
- Lock / Unlock
- Cabin Preconditioning (Heat/Cool)
- Battery SOC + Estimated Range (excellent Siri support)

---

## Features
- Uses official **BMW CarData** (MQTT streaming + REST)
- Proper HomeKit services (`LockMechanism`, `Battery`, `HeaterCooler`)
- Child Bridge friendly
- Designed for reliability and low resource usage

## Installation

1. Create a **Client ID** at [BMW CarData Portal](https://bmw-cardata.bmwgroup.com)
2. Install this plugin in Homebridge (`homebridge-bmhome`)
3. Add the platform with your `clientId`
4. Restart Homebridge

## Configuration Example

```json
{
  "platform": "BMWHome",
  "name": "BMW Home",
  "clientId": "your-client-id-here",
  "vin": "WBA00000000000000",
  "enableStreaming": true
}
