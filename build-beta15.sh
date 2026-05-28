set -euo pipefail

cd /Users/Jon/bmhome

echo "== BMHome v0.1.0-beta.15 logging cleanup and mapped state polish =="

npm login
npm whoami

rm -f homebridge-bmhome-*.tgz

node - <<'NODE'
const fs = require('fs');
const p = 'package.json';
const pkg = JSON.parse(fs.readFileSync(p, 'utf8'));
pkg.version = '0.1.0-beta.15';
pkg.repository = { type: 'git', url: 'git+https://github.com/JayC68/bmhome.git' };
pkg.bugs = { url: 'https://github.com/JayC68/bmhome/issues' };
pkg.homepage = 'https://bmhome.kernowekconsulting.co.uk';
fs.writeFileSync(p, JSON.stringify(pkg, null, 2) + '\n');
NODE

python3 <<'PY'
from pathlib import Path
import re

p = Path("src/bmwClient.ts")
s = p.read_text()

# Add lightweight log suppression fields.
if "private lastMqttAuthErrorLogAt" not in s:
    s = s.replace(
        "private descriptorState: Record<string, any> = {};",
        """private descriptorState: Record<string, any> = {};
  private lastMqttAuthErrorLogAt = 0;
  private lastMqttCloseLogAt = 0;
  private lastParsedSummary = '';
"""
    )

# Add helper if missing.
if "private shouldLogEvery" not in s:
    s = s.replace(
        "  private handleMqttMessage",
        """  private shouldLogEvery(key: 'auth' | 'close', intervalMs: number): boolean {
    const now = Date.now();

    if (key === 'auth') {
      if (now - this.lastMqttAuthErrorLogAt < intervalMs) {
        return false;
      }
      this.lastMqttAuthErrorLogAt = now;
      return true;
    }

    if (now - this.lastMqttCloseLogAt < intervalMs) {
      return false;
    }
    this.lastMqttCloseLogAt = now;
    return true;
  }

  private handleMqttMessage"""
    )

# Silence raw payload dumps by default, keeping one useful descriptor line.
s = re.sub(
    r"""this\.mqttClient\.on\('message', \(receivedTopic, payload\) => \{[\s\S]*?this\.handleMqttMessage\(receivedTopic, payload\);\s*\}\);""",
    """this.mqttClient.on('message', (receivedTopic, payload) => {
      this.lastMqttMessageAt = new Date();
      this.lastMqttTopic = receivedTopic;
      this.handleMqttMessage(receivedTopic, payload);
    });""",
    s,
    count=1
)

# Replace noisy MQTT error handler.
s = re.sub(
    r"""this\.mqttClient\.on\('error', \(err\) => \{[\s\S]*?\}\);""",
    """this.mqttClient.on('error', (err) => {
      const message = err?.message || String(err);

      if (/Bad username or password/i.test(message)) {
        if (this.shouldLogEvery('auth', 10 * 60 * 1000)) {
          console.error('[BMWClient] MQTT authentication failed. Token may be expired; BMHome will retry quietly.');
        }
        return;
      }

      console.error(`[BMWClient] MQTT error: ${message}`);
    });""",
    s,
    count=1
)

# Replace noisy close/reconnect/offline handlers.
s = re.sub(
    r"""this\.mqttClient\.on\('close', \(\) => \{[\s\S]*?\}\);""",
    """this.mqttClient.on('close', () => {
      this.mqttConnected = false;
      if (this.shouldLogEvery('close', 10 * 60 * 1000)) {
        console.warn('[BMWClient] MQTT connection closed; reconnecting quietly.');
      }
    });""",
    s,
    count=1
)

s = re.sub(
    r"""this\.mqttClient\.on\('reconnect', \(\) => \{[\s\S]*?\}\);""",
    """this.mqttClient.on('reconnect', () => {
      // Suppressed by default to avoid Homebridge log noise.
    });""",
    s,
    count=1
)

s = re.sub(
    r"""this\.mqttClient\.on\('offline', \(\) => \{[\s\S]*?\}\);""",
    """this.mqttClient.on('offline', () => {
      // Suppressed by default to avoid Homebridge log noise.
    });""",
    s,
    count=1
)

# De-duplicate parsed summary logs.
old = """      console.log(
        `[BMWClient] Parsed vehicle state: ` +
        `SOC=${data.soc ?? 'unknown'} ` +
        `Range=${data.remainingRange ?? 'unknown'} ` +
        `Charging=${data.isCharging ?? 'unknown'} ` +
        `Lock=${data.lockStatus ?? 'unknown'} ` +
        `DoorsOpen=${data.doorsOpen ?? 'unknown'} ` +
        `WindowsOpen=${data.windowsOpen ?? 'unknown'} ` +
        `Tyres=${tyrePressures.length}/4`
      );"""
new = """      const summary =
        `SOC=${data.soc ?? 'unknown'} ` +
        `Range=${data.remainingRange ?? 'unknown'} ` +
        `Charging=${data.isCharging ?? 'unknown'} ` +
        `Lock=${data.lockStatus ?? 'unknown'} ` +
        `DoorsOpen=${data.doorsOpen ?? 'unknown'} ` +
        `WindowsOpen=${data.windowsOpen ?? 'unknown'} ` +
        `Tyres=${tyrePressures.length}/4`;

      if (summary !== this.lastParsedSummary) {
        this.lastParsedSummary = summary;
        console.log(`[BMWClient] Parsed vehicle state: ${summary}`);
      }"""
s = s.replace(old, new)

p.write_text(s)
PY

npm install
npm run build

node - <<'NODE'
const fs = require('fs');
const s = fs.readFileSync('dist/bmwClient.js', 'utf8');
if (!s.includes('descriptorState')) throw new Error('descriptorState missing');
if (!s.includes('shouldLogEvery')) throw new Error('log suppression helper missing');
if (!s.includes('MQTT authentication failed')) throw new Error('quiet auth message missing');
if (s.includes('MQTT RAW PAYLOAD START')) throw new Error('raw payload spam still present');
if (!s.includes('lastParsedSummary')) throw new Error('parsed summary de-dupe missing');
console.log('Validation OK');
NODE

npm pack --dry-run

git add package.json package-lock.json src/bmwClient.ts
git add -u package.json package-lock.json src/bmwClient.ts
git commit -m "Reduce MQTT log noise and polish mapped state logging"

git push -u origin "$(git branch --show-current)"

npm publish

npm view homebridge-bmhome@0.1.0-beta.15 version description

echo "== BMHome beta.15 complete =="
