const fs = require('fs');

const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8'));
const dist = fs.readFileSync('dist/vehicleAccessory.js', 'utf8');
const src = fs.readFileSync('src/vehicleAccessory.ts', 'utf8');

if (pkg.version !== '0.1.0-beta.31') throw new Error('package version is not beta.31');
if (pkg.displayName !== 'BM Home Stream') throw new Error('displayName is not BM Home Stream');

const required = ['BMW Battery', 'BMW Windows', 'BMW Boot', 'BMW Tyres'];
const forbidden = ['BMW Lock','LockMechanism','LockTargetState','LockCurrentState','lockService','BMW Preconditioning','HeaterCooler'];

for (const t of required) {
  if (!dist.includes(t)) throw new Error(`${t} missing from dist`);
}
for (const t of forbidden) {
  if (dist.includes(t)) throw new Error(`${t} remains in dist`);
  if (src.includes(t)) throw new Error(`${t} remains in src`);
}

console.log('Validation OK');
