const fs = require('fs');

const p = 'package.json';
const pkg = JSON.parse(fs.readFileSync(p, 'utf8'));

pkg.version = '0.1.0-beta.29';
pkg.description = 'BMHome - Apple Home integration for BMW vehicles using BMW CarData Stream';
pkg.repository = { type: 'git', url: 'git+https://github.com/JayC68/bmhome.git' };
pkg.bugs = { url: 'https://github.com/JayC68/bmhome/issues' };
pkg.homepage = 'https://bmhome.kernowekconsulting.co.uk';

pkg.keywords = [
  'homebridge-plugin',
  'homebridge',
  'bmhome',
  'bmw',
  'mini',
  'apple-home',
  'homekit',
  'cardata',
  'connecteddrive'
];

pkg.engines = {
  node: '^22.0.0 || ^24.0.0',
  homebridge: '^1.8.0 || ^2.0.0'
};

fs.writeFileSync(p, JSON.stringify(pkg, null, 2) + '\n');
