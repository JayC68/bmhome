set -euo pipefail

cd /Users/Jon/bmhome
echo "== BMHome v0.1.0-beta.21 battery descriptor discovery =="

npm login
npm whoami
rm -f homebridge-bmhome-*.tgz

node - <<'NODE'
const fs = require('fs');
const p = 'package.json';
const pkg = JSON.parse(fs.readFileSync(p, 'utf8'));
pkg.version = '0.1.0-beta.21';
pkg.repository = { type: 'git', url: 'git+https://github.com/JayC68/bmhome.git' };
pkg.bugs = { url: 'https://github.com/JayC68/bmhome/issues' };
pkg.homepage = 'https://bmhome.kernowekconsulting.co.uk';
fs.writeFileSync(p, JSON.stringify(pkg, null, 2) + '\n');
NODE

python3 <<'PY'
from pathlib import Path

p = Path("src/bmwClient.ts")
s = p.read_text()

if "private discoveredDescriptorPaths" not in s:
    s = s.replace(
        "private descriptorState: Record<string, any> = {};",
        """private descriptorState: Record<string, any> = {};
  private discoveredDescriptorPaths = new Set<string>();"""
    )

if "private logCandidateDescriptors" not in s:
    s = s.replace(
        "  private detectVehicleBrand",
"""  private logCandidateDescriptors(data: Record<string, any>): void {
    const patterns = [
      /battery/i,
      /soc/i,
      /charge/i,
      /charging/i,
      /energy/i,
      /hv/i
    ];

    for (const [path, entry] of Object.entries(data || {})) {
      if (this.discoveredDescriptorPaths.has(path)) {
        continue;
      }

      if (!patterns.some((pattern) => pattern.test(path))) {
        continue;
      }

      this.discoveredDescriptorPaths.add(path);

      const value = entry && typeof entry === 'object' && 'value' in entry
        ? (entry as any).value
        : entry;

      const unit = entry && typeof entry === 'object' && 'unit' in entry
        ? ` ${(entry as any).unit}`
        : '';

      console.log(`[BMWClient] Candidate battery/charge descriptor: ${path} = ${JSON.stringify(value)}${unit}`);
    }
  }

  private detectVehicleBrand"""
    )

if "this.logCandidateDescriptors(json.data);" not in s:
    s = s.replace(
"""      if (json?.data && typeof json.data === 'object') {
        Object.assign(this.descriptorState, json.data);
      }""",
"""      if (json?.data && typeof json.data === 'object') {
        Object.assign(this.descriptorState, json.data);
        this.logCandidateDescriptors(json.data);
      }"""
    )

p.write_text(s)
PY

npm install
npm run build

node - <<'NODE'
const fs = require('fs');
const s = fs.readFileSync('dist/bmwClient.js', 'utf8');
for (const term of [
  'discoveredDescriptorPaths',
  'logCandidateDescriptors',
  'Candidate battery/charge descriptor',
  'battery',
  'charging',
  'energy',
  'soc'
]) {
  if (!s.includes(term)) throw new Error(term + ' missing');
}
if (s.includes('MQTT RAW PAYLOAD START')) throw new Error('raw payload spam returned');
if (s.includes('MQTT vehicle update received')) throw new Error('update spam returned');
console.log('Validation OK');
NODE

npm pack --dry-run

git add package.json package-lock.json src/bmwClient.ts
git add -u package.json package-lock.json src/bmwClient.ts
git commit -m "Add battery and charging descriptor discovery"

git push -u origin "$(git branch --show-current)"

npm publish

npm view homebridge-bmhome@0.1.0-beta.21 version description

echo "== BMHome beta.21 complete =="
