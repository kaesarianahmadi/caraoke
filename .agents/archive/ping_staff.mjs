import { dispatchToWorker } from './staff_caller.mjs';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const MODELS = JSON.parse(fs.readFileSync(path.join(__dirname, 'staff_models.json'), 'utf8'));
const SOULS = {
  axel: path.join(__dirname, 'swiftui-builder.soul.md'),
  vance: path.join(__dirname, 'silent-failure-hunter.soul.md'),
  ward: path.join(__dirname, 'store-security-gatekeeper.soul.md')
};

const pings = Object.entries(MODELS).map(async ([worker, tiers]) => {
  const soul = fs.readFileSync(SOULS[worker], 'utf8');
  for (const [tier, model] of Object.entries(tiers)) {
    const r = await dispatchToWorker(worker, model, soul, `PING from Josh: system-smoothness check. Reply with one short sentence confirming you are online, your name, and your role. No code.`, []);
    console.log(`[RESULT] ${worker}/${tier} model=${model} ok=${!r.errorMsg} ${r.durationMs}ms :: ${(r.responseText || r.errorMsg || '').slice(0, 80)}`);
  }
});
await Promise.all(pings);
console.log('ALL PINGS DONE');
