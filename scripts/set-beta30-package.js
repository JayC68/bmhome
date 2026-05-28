const fs = require('fs');

const pkgPath = './package.json';
const pkg = JSON.parse(fs.readFileSync(pkgPath, 'utf8'));

pkg.version = '0.1.0-beta.30';

pkg.description =
  'BMW CarData telemetry for Apple Home via Homebridge';

pkg.displayName = 'BM Home';

pkg.keywords = [
  'homebridge-plugin',
  'bmw',
  'mini',
  'cardata',
  'mqtt',
  'apple-home',
  'homekit',
  'telemetry',
  'ev'
];

fs.writeFileSync(pkgPath, JSON.stringify(pkg, null, 2) + '\n');

console.log('Updated package.json -> 0.1.0-beta.30');
