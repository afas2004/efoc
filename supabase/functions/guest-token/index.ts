// POST /functions/v1/guest-token
// Redeems a one-time guest pass (public.game_guest_passes) for a card-game
// table and answers a Firebase custom token for "guest-<uuid>" with claims
// { guest_room, guest_until }. The Realtime Database rules let that uid
// into that one room until guest_until. No Supabase account is made.
//
// Body: { pass, name, device_key }
//   device_key: a random string the browser keeps (localStorage). The first
//   browser to redeem the pass owns it; the same browser may redeem again
//   (page refresh) until it expires, any other browser is refused.
//
// Deploy: npx supabase functions deploy guest-token --no-verify-jwt --project-ref <ref> --use-api
// Secrets: FIREBASE_SERVICE_ACCOUNT (same as firebase-token).

import { createClient } from "jsr:@supabase/supabase-js@2";
import { mintCustomToken, type ServiceAccount } from "../firebase-token/token.ts";

const ORIGINS = [/^https:\/\/(www\.)?efoc\.party$/, /^http:\/\/localhost(:\d+)?$/, /^http:\/\/127\.0\.0\.1(:\d+)?$/];
const PASS = /^[A-Z0-9]{12}$/;

function cors(origin: string | null): Record<string, string> {
  const ok = origin && ORIGINS.some((r) => r.test(origin));
  return {
    ...(ok ? { "Access-Control-Allow-Origin": origin! } : {}),
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    Vary: "Origin",
  };
}

async function sha256(text: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, "0")).join("");
}

let account: ServiceAccount | null = null;
function serviceAccount(): ServiceAccount {
  if (!account) {
    const raw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT");
    if (!raw) throw new Error("FIREBASE_SERVICE_ACCOUNT is not set");
    account = JSON.parse(raw) as ServiceAccount;
  }
  return account;
}

Deno.serve(async (req) => {
  const headers = cors(req.headers.get("origin"));
  const json = (status: number, body: unknown) =>
    new Response(JSON.stringify(body), { status, headers: { ...headers, "Content-Type": "application/json" } });

  if (req.method === "OPTIONS") return new Response("ok", { headers });
  if (req.method !== "POST") return json(405, { error: "POST only" });

  let body: Record<string, unknown> = {};
  try {
    body = await req.json();
  } catch {
    // fall through
  }
  const pass = String(body.pass ?? "").toUpperCase().replace(/[^A-Z0-9]/g, "");
  const name = String(body.name ?? "").replace(/\s+/g, " ").trim();
  const deviceKey = String(body.device_key ?? "");

  if (!PASS.test(pass)) return json(400, { error: "That guest link isn't valid" });
  if (name.length < 1 || name.length > 20) return json(400, { error: "Name: 1–20 characters" });
  if (deviceKey.length < 16 || deviceKey.length > 128) return json(400, { error: "Bad device key" });

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  admin.rpc("purge_game_guest_passes").then(() => {}, () => {});

  const deviceHash = await sha256(deviceKey);
  const cols = "room_id, group_id, game_id, expires_at, redeemed_at, device_hash, guest_uid, guest_name";

  const { data: row } = await admin.from("game_guest_passes").select(cols).eq("code", pass).maybeSingle();
  if (!row) return json(404, { error: "That guest link isn't valid" });
  if (new Date(row.expires_at).getTime() <= Date.now()) return json(410, { error: "That guest link has expired" });

  let guest = row;
  if (!row.redeemed_at) {
    // Only the first redeem wins: the update matches only while unredeemed.
    const { data: claimed } = await admin
      .from("game_guest_passes")
      .update({
        redeemed_at: new Date().toISOString(),
        device_hash: deviceHash,
        guest_uid: `guest-${crypto.randomUUID()}`,
        guest_name: name,
      })
      .eq("code", pass)
      .is("redeemed_at", null)
      .select(cols)
      .maybeSingle();
    if (claimed) {
      guest = claimed;
    } else {
      const { data: again } = await admin.from("game_guest_passes").select(cols).eq("code", pass).maybeSingle();
      if (!again) return json(404, { error: "That guest link isn't valid" });
      guest = again;
    }
  }
  if (guest.device_hash !== deviceHash) return json(409, { error: "That guest link was already used" });

  const until = new Date(guest.expires_at).getTime();
  try {
    const token = await mintCustomToken(serviceAccount(), guest.guest_uid, undefined, {
      guest_room: guest.room_id,
      guest_until: until,
    });
    return json(200, {
      token,
      uid: guest.guest_uid,
      name: guest.guest_name,
      room_id: guest.room_id,
      group_id: guest.group_id,
      game_id: guest.game_id,
      expires_at: guest.expires_at,
    });
  } catch (e) {
    console.error("guest-token:", e);
    return json(500, { error: "Couldn't make a game token" });
  }
});
