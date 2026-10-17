// node supabase/functions/firebase-token/token.test.mjs
// Signs a token with a throwaway key and checks it the way Firebase does.
import { generateKeyPairSync, createVerify } from 'node:crypto';
import { readFileSync, writeFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import assert from 'node:assert/strict';

// token.ts is plain TypeScript with type-only syntax; strip it for Node.
const here = new URL('.', import.meta.url);
const ts = readFileSync(new URL('token.ts', here), 'utf8');
const { stripTypeScriptTypes } = await import('node:module');
const dir = mkdtempSync(join(tmpdir(), 'fbtoken-'));
const file = join(dir, 'token.mjs');
writeFileSync(file, stripTypeScriptTypes(ts));
const { mintCustomToken } = await import(pathToFileURL(file).href);

const { privateKey, publicKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
const pem = privateKey.export({ type: 'pkcs8', format: 'pem' });
// The JSON from the console has "\n" escapes; both forms must work.
for (const key of [pem, pem.replace(/\n/g, '\\n')]) {
  const sa = { client_email: 'svc@efoc-fcf44.iam.gserviceaccount.com', private_key: key };
  const token = await mintCustomToken(sa, 'c0ffee00-1111-2222-3333-444455556666', 1_800_000_000);
  const [h, p, s] = token.split('.');
  const dec = (x) => JSON.parse(Buffer.from(x, 'base64url').toString());
  assert.deepEqual(dec(h), { alg: 'RS256', typ: 'JWT' });
  const payload = dec(p);
  assert.equal(payload.uid, 'c0ffee00-1111-2222-3333-444455556666');
  assert.equal(payload.iss, sa.client_email);
  assert.equal(payload.sub, sa.client_email);
  assert.equal(payload.aud, 'https://identitytoolkit.googleapis.com/google.identity.identitytoolkit.v1.IdentityToolkit');
  assert.equal(payload.exp - payload.iat, 3600);
  const ok = createVerify('RSA-SHA256').update(`${h}.${p}`).verify(publicKey, Buffer.from(s, 'base64url'));
  assert.ok(ok, 'signature verifies');
}
await assert.rejects(mintCustomToken({ client_email: 'x', private_key: pem }, ''));
console.log('firebase-token: ok');
