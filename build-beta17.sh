set -euo pipefail

cd /Users/Jon/bmhome

echo "== BMHome v0.1.0-beta.17 remove MQTT update spam =="

npm login
npm whoami

rm -f homebridge-bmhome-*.tgz

node - <<'NODE'
const fs = require('fs');
const p = 'package.json';
const pkg = JSON.parse(fs.readFileSync(p, 'utf8'));
pkg.version = '0.1.0-beta.17';
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

s = re.sub(
    r"\n\s*console\.log\(`$begin:math:display$BMWClient$end:math:display$ MQTT vehicle update received for \$\{vin\}`\);",
    "",
    s
)

p.write_text(s)
PY

npm install
npm run build

node - <<'NODE'
const fs = require('fs');
const s = fs.readFileSync('dist/bmwClient.js', 'utf8');
if (s.includes('MQTT vehicle update received for')) throw new Error('MQTT update spam remains');
if (!s.includes('Range=${')) throw new Error('range summary missing');
if (!s.includes('0.621371')) throw new Error('mile conversion missing');
console.log('Validation OK');
NODE

npm pack --dry-run

git add package.json package-lock.json src/bmwClient.ts
git add -u package.json package-lock.json src/bmwClient.ts

git commit -m "Remove MQTT vehicle update spam"

git push -u origin "$(git branch --show-current)"

npm publish

npm view homebridge-bmhome@0.1.0-beta.17 version description

echo "== BMHome beta.17 complete =="
