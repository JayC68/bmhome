set -euo pipefail

cd /Users/Jon/bmhome

echo "== BMHome v0.1.0-beta.16 distance unit support =="

npm login
npm whoami

rm -f homebridge-bmhome-*.tgz

node - <<'NODE'
const fs = require('fs');
const p = 'package.json';
const pkg = JSON.parse(fs.readFileSync(p, 'utf8'));
pkg.version = '0.1.0-beta.16';
pkg.repository = { type: 'git', url: 'git+https://github.com/JayC68/bmhome.git' };
pkg.bugs = { url: 'https://github.com/JayC68/bmhome/issues' };
pkg.homepage = 'https://bmhome.kernowekconsulting.co.uk';
fs.writeFileSync(p, JSON.stringify(pkg, null, 2) + '\n');
NODE

node - <<'NODE'
const fs = require('fs');
const p = 'config.schema.json';
const schema = JSON.parse(fs.readFileSync(p, 'utf8'));

schema.schema = schema.schema || {};
schema.schema.properties = schema.schema.properties || {};

schema.schema.properties.distanceUnit = {
  title: 'Distance Unit',
  type: 'string',
  default: 'mi',
  enum: ['mi', 'km'],
  description: 'Display vehicle range in miles or kilometres. BMW CarData usually supplies kilometres.'
};

fs.writeFileSync(p, JSON.stringify(schema, null, 2) + '\n');
NODE

python3 <<'PY'
from pathlib import Path
import re

# Add type field if needed
tp = Path("src/types.ts")
if tp.exists():
    s = tp.read_text()
    if "distanceUnit" not in s:
        s = re.sub(
            r"(pollingInterval\?: number;)",
            r"\1\n  distanceUnit?: 'mi' | 'km';",
            s
        )
        tp.write_text(s)

p = Path("src/bmwClient.ts")
s = p.read_text()

# Add range conversion helpers after remainingRange block
if "const distanceUnit =" not in s:
    s = s.replace(
"""      const remainingRange =
        value('vehicle.drivetrain.electricEngine.kombiRemainingElectricRange') ??
        value('vehicle.drivetrain.lastRemainingRange');""",
"""      const remainingRange =
        value('vehicle.drivetrain.electricEngine.kombiRemainingElectricRange') ??
        value('vehicle.drivetrain.lastRemainingRange');

      const distanceUnit = this.config.distanceUnit === 'km' ? 'km' : 'mi';
      const remainingRangeKm = typeof remainingRange === 'number' ? remainingRange : undefined;
      const remainingRangeMiles = typeof remainingRangeKm === 'number'
        ? Math.round(remainingRangeKm * 0.621371)
        : undefined;
      const userRemainingRange = distanceUnit === 'km' ? remainingRangeKm : remainingRangeMiles;"""
    )

# Replace range fields in data object
s = s.replace(
"        remainingRange: typeof remainingRange === 'number' ? remainingRange : undefined,",
"""        remainingRange: userRemainingRange,
        remainingRangeKm,
        remainingRangeMiles,
        distanceUnit,"""
)

# Remove noisy per-payload received log
s = re.sub(
    r"\n\s*console\.log\(`$begin:math:display$BMWClient$end:math:display$ MQTT vehicle update received for \$\{vin\}`\);",
    "",
    s
)

# Add unit to summary range
s = s.replace(
"`Range=${data.remainingRange ?? 'unknown'} ` +",
"`Range=${data.remainingRange ?? 'unknown'}${data.remainingRange !== undefined ? data.distanceUnit : ''} ` +"
)

p.write_text(s)
PY

npm install
npm run build

node - <<'NODE'
const fs = require('fs');
const dist = fs.readFileSync('dist/bmwClient.js', 'utf8');
if (!dist.includes('distanceUnit')) throw new Error('distanceUnit missing');
if (!dist.includes('0.621371')) throw new Error('mile conversion missing');
if (dist.includes('MQTT vehicle update received for')) throw new Error('payload received spam remains');
const schema = fs.readFileSync('config.schema.json', 'utf8');
if (!schema.includes('Distance Unit')) throw new Error('schema distance unit missing');
console.log('Validation OK');
NODE

npm pack --dry-run

git add package.json package-lock.json config.schema.json src/bmwClient.ts src/types.ts
git add -u package.json package-lock.json config.schema.json src/bmwClient.ts src/types.ts
git commit -m "Add distance unit support for BMW range"

git push -u origin "$(git branch --show-current)"

npm publish

npm view homebridge-bmhome@0.1.0-beta.16 version description

echo "== BMHome beta.16 complete =="
