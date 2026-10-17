// POST /functions/v1/firebase-token
// Checks the caller's Supabase session and answers { token }: a Firebase
// custom token whose uid is the Supabase user id, so the card games'
// Realtime Database rules (allowed/{uid}, hands/{uid}, ...) see the same id
// as EFOC's groups.
//
// Secret (set with `supabase secrets set`, never in the repo):
//   FIREBASE_SERVICE_ACCOUNT  the service-account JSON from Firebase console
//                             (Project settings > Service accounts > Generate new private key)
// SUPABASE_URL and SUPABASE_ANON_KEY are provided by Supabase.

import { createClient } from 'jsr:@supabase/supabase-js@2';
import { mintCustomToken, type ServiceAccount } from './token.ts';

const ORIGINS = [/^https:\/\/(www\.)?efoc\.party$/, /^http:\/\/localhost(:\d+)?$/, /^http:\/\/127\.0\.0\.1(:\d+)?$/];

function cors(origin: string | null): Record<string, string> {
  const ok = origin && ORIGINS.some((r) => r.test(origin));
  return {
    ...(ok ? { 'Access-Control-Allow-Origin': origin! } : {}),
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    Vary: 'Origin',
  };
}

let account: ServiceAccount | null = null;
function serviceAccount(): ServiceAccount {
  if (!account) {
    const raw = Deno.env.get('FIREBASE_SERVICE_ACCOUNT');
    if (!raw) throw new Error('FIREBASE_SERVICE_ACCOUNT is not set');
    const sa = JSON.parse(raw) as ServiceAccount;
    if (!sa.client_email || !sa.private_key) throw new Error('FIREBASE_SERVICE_ACCOUNT is incomplete');
    account = sa;
  }
  return account;
}

Deno.serve(async (req) => {
  const headers = cors(req.headers.get('origin'));
  const json = (status: number, body: unknown) =>
    new Response(JSON.stringify(body), { status, headers: { ...headers, 'Content-Type': 'application/json' } });

  if (req.method === 'OPTIONS') return new Response('ok', { headers });
  if (req.method !== 'POST') return json(405, { error: 'POST only' });

  const jwt = (req.headers.get('authorization') ?? '').replace(/^Bearer\s+/i, '');
  if (!jwt) return json(401, { error: 'not signed in' });

  const supabase = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await supabase.auth.getUser(jwt);
  if (error || !data.user) return json(401, { error: 'not signed in' });

  try {
    const token = await mintCustomToken(serviceAccount(), data.user.id);
    return json(200, { token });
  } catch (e) {
    console.error('firebase-token:', e);
    return json(500, { error: 'could not make a game token' });
  }
});
