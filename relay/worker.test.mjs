import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
const source = await readFile(new URL('./worker.js', import.meta.url), 'utf8');
const { default: worker } = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);
let forwarded = 0;
const env = { LyricsSession: {
  idFromName: name => name,
  get: () => ({ fetch: async () => { forwarded++; return new Response('ok'); } }),
} };
for (const method of ['GET', 'DELETE']) {
  const response = await worker.fetch(new Request('https://relay.test/crashes', { method }), env);
  assert.equal(response.status, 405);
}
assert.equal(forwarded, 0, 'Public diagnostics must not reach stored crash reports');
const accepted = await worker.fetch(new Request('https://relay.test/crashes', { method: 'POST', body: '{}' }), env);
assert.equal(accepted.status, 200);
assert.equal(forwarded, 1);
console.log('Crash diagnostics: public read/delete rejected; ingestion preserved');
