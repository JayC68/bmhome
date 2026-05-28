set -euo pipefail

cd /Users/Jon/bmhome
echo "== BMHome v0.1.0-beta.22 finalise SOC parser and remove discovery noise =="

npm login
npm whoami
rm -f homebridge-bmhome-*.tgz

node - <<'NODE'
const fs = require('fs');
const p = 'package.json';
const pkg = JSON.parse(fs.readFileSync(p, 'utf8'));
pkg.version = '0.1.0-beta.22';
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

# Remove beta.21 discovery field and method.
s = s.replace("  private discoveredDescriptorPaths = new Set<string>();\n", "")

s = re.sub(
    r"\n  private logCandidateDescriptors\(data: Record<string, any>\): void \{[\s\S]*?\n  private detectVehicleBrand",
    "\n  private detectVehicleBrand",
    s,
    count=1
)

# Remove discovery call, keep descriptor cache.
s = s.replace(
"""      if (json?.data && typeof json.data === 'object') {
        Object.assign(this.descriptorState, json.data);
        this.logCandidateDescriptors(json.data);
      }""",
"""      if (json?.data && typeof json.data === 'object') {
        Object.assign(this.descriptorState, json.data);
      }"""
)

p.write_text(s)
PY

npm install
npm run build

node - <<'NODE'
const fs = require('fs');
const s = fs.readFileSync('dist/bmwClient.js', 'utf8');
if (!s.includes('vehicle.drivetrain.batteryManagement.header')) throw new Error('SOC header parser missing');
if (!s.includes('vehicle.trip.segment.end.drivetrain.batteryManagement.hvSoc')) throw new Error('SOC fallback parser missing');
if (s.includes('Candidate battery/charge descriptor')) throw new Error('discovery logging remains');
if (s.includes('logCandidateDescriptors')) throw new Error('discovery method remains');
if (s.includes('discoveredDescriptorPaths')) throw new Error('discovery state remains');
if (s.includes('MQTT RAW PAYLOAD START')) throw new Error('raw payload spam returned');
if (s.includes('MQTT vehicle update received')) throw new Error('update spam returned');
console.log('Validation OK');
NODE

npm pack --dry-run

git add package.json package-lock.json src/bmwClient.ts
git add -u package.json package-lock.json src/bmwClient.ts

git commit -m "Finalise BMW SOC parser and remove discovery logging"

git push -u origin "$(git branch --show-current)"

npm publish

npm view homebridge-bmhome@0.1.0-beta.22 version description

echo "== BMHome beta.22 complete =="
