import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const profiles = JSON.parse(fs.readFileSync(path.join(root, 'app', 'profiles.json'), 'utf8'));
const sources = JSON.parse(fs.readFileSync(path.join(root, 'app', 'engine-sources.json'), 'utf8'));

assert.equal(profiles.schemaVersion, 1);
assert.ok(profiles.profiles.length >= 5);
assert.equal(new Set(profiles.profiles.map((profile) => profile.id)).size, profiles.profiles.length);
for (const profile of profiles.profiles) {
  assert.match(profile.id, /^[a-z][a-z0-9-]+$/);
  assert.ok(profile.name.length >= 3);
  assert.ok(profile.strategyFile.toLowerCase().endsWith('.bat'));
  assert.ok(['low', 'medium', 'high'].includes(profile.risk));
}
assert.deepEqual(sources.sources.map((source) => source.id), ['flowseal', 'zapret1', 'zapret2']);
assert.equal(sources.sources[0].repository, 'Flowseal/zapret-discord-youtube');
assert.equal(sources.sources[0].allowedDownloadPrefix, 'https://github.com/Flowseal/zapret-discord-youtube/releases/download/');
assert.ok(sources.sources[0].maxAssetBytes > 0);


for (const requiredFile of ['FreeSignal.vbs', 'assets/freesignal.ico', 'app/MainWindow.ru.xaml', 'docs/TEST_MATRIX.md']) {
  assert.ok(fs.existsSync(path.join(root, requiredFile)), `Missing ${requiredFile}`);
}

const script = fs.readFileSync(path.join(root, 'FreeSignal.ps1'), 'utf8');
for (const requiredFunction of ['Install-FSLatestFlowsealEngine', 'Invoke-FSAutoOptimization', 'Start-FSWatchdog', 'Stop-FSEngine', 'Invoke-FSDiagnostics', 'New-FSRuntimeStrategy', 'Test-FSArchiveSafety', 'Save-FSManagedProcesses']) {
  assert.ok(script.includes(`function ${requiredFunction}`), `Missing ${requiredFunction}`);
}
assert.ok(!script.includes('Set-MpPreference'), 'The app must never disable Microsoft Defender.');
assert.ok(!script.includes('Add-MpPreference'), 'The app must never add antivirus exclusions.');
console.log(`Profiles and safety invariants passed (${profiles.profiles.length} profiles, ${sources.sources.length} adapters).`);

assert.ok(script.includes('service.bat hooks were not executed'), 'The client must use the sanitized strategy path.');
assert.ok(script.includes('FreeSignal will not stop or take ownership of external tools'), 'External winws processes must be protected.');
