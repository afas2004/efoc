// Firebase custom token (a JWT signed with the service account's key), made
// with Web Crypto only, so it runs on Supabase Edge Functions (Deno) and in
// the Node test next to it. Format:
// https://firebase.google.com/docs/auth/admin/create-custom-tokens#create_custom_tokens_using_a_third-party_jwt_library

export interface ServiceAccount {
  client_email: string;
  private_key: string;
}

const AUD = 'https://identitytoolkit.googleapis.com/google.identity.identitytoolkit.v1.IdentityToolkit';

const b64url = (bytes: Uint8Array): string => {
  let s = '';
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
};

const b64urlJson = (v: unknown): string => b64url(new TextEncoder().encode(JSON.stringify(v)));

async function importKey(pem: string): Promise<CryptoKey> {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\\n/g, '') // a key pasted with literal backslash-n escapes
    .replace(/\s+/g, '');
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey('pkcs8', der, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
}

/** A custom token for `uid`, valid for one hour (Firebase's maximum). */
export async function mintCustomToken(sa: ServiceAccount, uid: string, nowSec = Math.floor(Date.now() / 1000)): Promise<string> {
  if (!uid || uid.length > 128) throw new Error('bad uid');
  const header = { alg: 'RS256', typ: 'JWT' };
  const payload = { iss: sa.client_email, sub: sa.client_email, aud: AUD, iat: nowSec, exp: nowSec + 3600, uid };
  const input = `${b64urlJson(header)}.${b64urlJson(payload)}`;
  const key = await importKey(sa.private_key);
  const sig = new Uint8Array(await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(input)));
  return `${input}.${b64url(sig)}`;
}
