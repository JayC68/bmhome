const fs = require('fs');

const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8'));
const accessory = fs.readFileSync('dist/vehicleAccessory.js', 'utf8');
const readme = fs.readFileSync('README.md', 'utf8');
const changelog = fs.readFileSync('CHANGELOG.md', 'utf8');
const releaseNotes = fs.readFileSync('.homebridge/release-notes.md', 'utf8');

if (pkg.version !== '0.1.0-beta.29') throw new Error('version not beta.29');
if (!pkg.engines?.homebridge?.includes('2.0.0')) throw new Error('Homebridge 2.x engine missing');
if (!pkg.engines?.node?.includes('24.0.0')) throw new Error('Node 24 engine missing');

for (const term of ['BMW Battery', 'BMW Lock', 'BMW Windows', 'BMW Boot', 'BMW Tyres']) {
  if (!accessory.includes(term)) throw new Error(term + ' tile missing');
}

for (const term of ['HeaterCooler', 'BMW Preconditioning', 'preconditionActive']) {
  if (accessory.includes(term)) throw new Error(term + ' legacy preconditioning remains');
}

for (const term of ['Your BMW, integrated into Apple Home.', 'Fed by BMW’s CarData Stream.', 'Recommended Descriptors']) {
  if (!readme.includes(term)) throw new Error(term + ' missing from README');
}

if (!changelog.includes('0.1.0-beta.29')) throw new Error('CHANGELOG beta.29 missing');
if (!releaseNotes.includes('BMHome 0.1.0-beta.29')) throw new Error('release notes beta.29 missing');

console.log('Validation OK');
