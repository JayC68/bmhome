const fs = require('fs');

const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8'));
const files = ['src/vehicleAccessory.ts', 'src/types.ts', 'src/platform.ts', 'src/bmwClient.ts', 'dist/vehicleAccessory.js', 'dist/bmwClient.js'];
const text = Object.fromEntries(files.map(f => [f, fs.readFileSync(f, 'utf8')]));

if (pkg.version !== '0.1.0-beta.32') throw new Error('package version is not beta.32');
if (pkg.displayName !== 'BM Home Stream') throw new Error('displayName is not BM Home Stream');

for (const t of ['BMW Battery', 'BMW Windows', 'BMW Boot', 'BMW Tyres']) {
  if (!text['dist/vehicleAccessory.js'].includes(t)) throw new Error(`${t} missing from dist accessory`);
}

const forbidden = [
  'BMW Lock', 'LockMechanism', 'LockTargetState', 'LockCurrentState', 'lockService',
  'BMW Preconditioning', 'HeaterCooler', 'CommandResponse', 'async lock(', 'async unlock(',
  'precondition(', 'Lock=', 'normaliseLockStatus'
];

for (const term of forbidden) {
  for (const [file, contents] of Object.entries(text)) {
    if (contents.includes(term)) throw new Error(`${term} remains in ${file}`);
  }
}

const readme = fs.readFileSync('README.md', 'utf8');
for (const term of ['BM Home Stream', 'telemetry', 'Why BM Home Stream Does Not Lock or Unlock the Car']) {
  if (!readme.includes(term)) throw new Error(`${term} missing from README`);
}

console.log('Validation OK');
