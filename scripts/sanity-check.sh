#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="/Users/Jon/bmhome"
cd "$PROJECT_DIR"

echo "== BMHome Sanity Check =="

fail() {
  echo "❌ $1"
  exit 1
}

pass() {
  echo "✅ $1"
}

warn() {
  echo "⚠️  $1"
}

echo
echo "1. Repository checks"
git rev-parse --is-inside-work-tree >/dev/null || fail "Not inside a git repository"
git status --short
pass "Git repository detected"

echo
echo "2. Required file checks"
for file in package.json tsconfig.json config.schema.json src/index.ts src/platform.ts src/bmwClient.ts src/configValidator.ts src/vehicleAccessory.ts; do
  [ -f "$file" ] || fail "Missing required file: $file"
done
pass "Required files present"

echo
echo "3. package.json checks"
node <<'NODE'
const fs = require('fs');
const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8'));

function fail(msg) {
  console.error(`❌ ${msg}`);
  process.exit(1);
}

if (pkg.name !== 'homebridge-bmhome') fail('package name should be homebridge-bmhome');
if (!pkg.displayName || pkg.displayName !== 'BM Home') fail('displayName should be BM Home');
if (!pkg.main || pkg.main !== 'dist/index.js') fail('main should be dist/index.js');
if (!pkg.keywords || !pkg.keywords.includes('homebridge-plugin')) fail('missing homebridge-plugin keyword');
if (!pkg.engines || !pkg.engines.node) fail('missing node engine');
if (!pkg.engines || !pkg.engines.homebridge) fail('missing homebridge engine');
if (!pkg.scripts || !pkg.scripts.build) fail('missing build script');

console.log('✅ package.json metadata looks good');
NODE

echo
echo "4. config.schema.json checks"
node <<'NODE'
const fs = require('fs');
const schema = JSON.parse(fs.readFileSync('config.schema.json', 'utf8'));

function fail(msg) {
  console.error(`❌ ${msg}`);
  process.exit(1);
}

if (schema.pluginAlias !== 'BMWHome' && schema.pluginAlias !== 'BMHome') {
  fail('pluginAlias should be BMWHome or BMHome');
}

if (schema.pluginType !== 'platform') fail('pluginType should be platform');
if (!schema.schema) fail('missing schema object');
if (!schema.schema.properties) fail('missing schema properties');
if (!schema.schema.properties.clientId) fail('missing clientId property');
if (!schema.schema.required || !schema.schema.required.includes('clientId')) fail('clientId should be required');

console.log('✅ config.schema.json looks good');
NODE

echo
echo "5. Dependency install check"
npm install
pass "Dependencies installed"

echo
echo "6. TypeScript build"
npm run build
pass "TypeScript build passed"

echo
echo "7. Runtime output checks"
[ -f dist/index.js ] || fail "dist/index.js missing after build"
[ -f dist/platform.js ] || fail "dist/platform.js missing after build"
[ -f dist/bmwClient.js ] || fail "dist/bmwClient.js missing after build"
[ -f dist/configValidator.js ] || fail "dist/configValidator.js missing after build"
[ -f dist/vehicleAccessory.js ] || fail "dist/vehicleAccessory.js missing after build"
pass "Compiled dist files present"

echo
echo "8. Config validator smoke test"
node <<'NODE'
const { validateConfig } = require('./dist/configValidator');

function fail(msg) {
  console.error(`❌ ${msg}`);
  process.exit(1);
}

try {
  const config = validateConfig({
    platform: 'BMWHome',
    name: 'BM Home',
    clientId: 'test-client-id-12345',
    vin: '',
    enableStreaming: true,
    pollingInterval: 180,
  });

  if (!config.clientId) fail('validated config missing clientId');
  if (config.name !== 'BM Home') fail('validated config name mismatch');
} catch (err) {
  fail(`valid config rejected: ${err.message}`);
}

try {
  validateConfig({
    platform: 'BMWHome',
    name: 'BM Home',
  });
  fail('invalid config without clientId was accepted');
} catch {
  // expected
}

console.log('✅ Config validator smoke test passed');
NODE

echo
echo "9. Basic source safety checks"

if grep -RIn --exclude-dir=node_modules --exclude-dir=dist --exclude='*.bak.*' \
  -E "(password|secret|token|client_secret|api_key|apikey)\s*[:=]\s*['\"][^'\"]{8,}" .; then
  warn "Potential hardcoded secret-like strings found. Review above."
else
  pass "No obvious hardcoded secrets found"
fi

if grep -RIn --exclude-dir=node_modules --exclude-dir=dist --exclude='*.bak.*' \
  -E "eval\(|new Function\(|child_process|execSync|spawnSync|curl |wget " src package.json; then
  warn "Potentially risky execution patterns found. Review above."
else
  pass "No obvious risky execution patterns found"
fi

echo
echo "10. npm audit"
if npm audit --audit-level=high; then
  pass "No high/critical npm audit issues"
else
  fail "npm audit found high or critical issues"
fi

echo
echo "11. Package contents dry run"
npm pack --dry-run
pass "npm package dry-run passed"

echo
echo "12. Homebridge plugin metadata smoke check"
node <<'NODE'
const fs = require('fs');
const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8'));

function fail(msg) {
  console.error(`❌ ${msg}`);
  process.exit(1);
}

const packedName = `${pkg.name}-${pkg.version}.tgz`;

if (!pkg.name.startsWith('homebridge-')) fail('package name should start with homebridge-');
if (!pkg.keywords.includes('homebridge-plugin')) fail('missing homebridge-plugin keyword');
if (!pkg.main.startsWith('dist/')) fail('main should point at dist output');

console.log(`✅ Homebridge metadata OK for ${pkg.name}@${pkg.version}`);
NODE

echo
echo "13. Git cleanliness summary"
if git diff --quiet && git diff --cached --quiet; then
  pass "Working tree clean"
else
  warn "Working tree has uncommitted changes"
  git status --short
fi

echo
echo "== BMHome sanity check complete =="
echo "Result: GOOD, assuming any warnings above have been reviewed."
