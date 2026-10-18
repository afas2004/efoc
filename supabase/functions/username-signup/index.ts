// POST /functions/v1/username-signup
// Creates an account with just a username, no email. Only people holding
// a Log invite code can sign up.
//
// Body: { username, display_name?, invite_code }
// Creates the user, sets their profile name, adds them to the Log as a
// member, and answers { ok: true, recovery_code }. The recovery code is
// the account's password: we make it here, store only its hash (Supabase
// Auth), and the app shows it once. The app then signs in with
// signInWithPassword (email = `${username}@users.efoc.party`, password =
// the code without dashes), so the Log is already there on the home screen.
//
// The address is internal only: users.efoc.party has no mail server, so
// nothing is ever sent to it, and the email login refuses that domain.
//
// Deploy: npx supabase functions deploy username-signup --no-verify-jwt --project-ref <ref> --use-api
// (--no-verify-jwt because the caller isn't signed in yet.)

import { createClient } from "jsr:@supabase/supabase-js@2";

const DOMAIN = "users.efoc.party";
const USERNAME = /^[a-z0-9_]{3,20}$/;
const CODE = /^[A-Z0-9]{6}$/;
// Same alphabet as invite codes: no 0/O, 1/I/L.
const ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";

// 12 characters ≈ 59 bits, shown as XXXX-XXXX-XXXX.
function recoveryCode(): string {
  const out: string[] = [];
  const bytes = new Uint8Array(1);
  while (out.length < 12) {
    crypto.getRandomValues(bytes);
    if (bytes[0] < 248) out.push(ALPHABET[bytes[0] % ALPHABET.length]); // 248 = 8 × 31, no bias
  }
  return out.join("");
}

const ORIGINS = [/^https:\/\/(www\.)?efoc\.party$/, /^http:\/\/localhost(:\d+)?$/, /^http:\/\/127\.0\.0\.1(:\d+)?$/];

function cors(origin: string | null): Record<string, string> {
  const ok = origin && ORIGINS.some((r) => r.test(origin));
  return {
    ...(ok ? { "Access-Control-Allow-Origin": origin! } : {}),
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    Vary: "Origin",
  };
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
    // fall through to the checks below
  }
  const username = String(body.username ?? "").trim().toLowerCase();
  const code = String(body.invite_code ?? "").trim().toUpperCase();
  const displayName = String(body.display_name ?? "").trim().slice(0, 40) || username;

  if (!USERNAME.test(username)) {
    return json(400, { error: "Username: 3–20 letters, numbers or _" });
  }
  if (!CODE.test(code)) return json(400, { error: "Invite code must be 6 characters" });

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: group } = await admin
    .from("groups")
    .select("id")
    .eq("invite_code", code)
    .eq("is_personal", false)
    .maybeSingle();
  if (!group) return json(404, { error: "That invite code doesn't match any Log" });

  const { count } = await admin
    .from("profiles")
    .select("id", { count: "exact", head: true })
    .ilike("username", username.replaceAll("_", "\\_")); // _ is a LIKE wildcard
  if ((count ?? 0) > 0) return json(409, { error: "That username is taken" });

  const password = recoveryCode();
  const { data: created, error } = await admin.auth.admin.createUser({
    email: `${username}@${DOMAIN}`,
    password,
    email_confirm: true,
    user_metadata: { username, display_name: displayName, no_email: true },
  });
  if (error || !created.user) {
    const taken = /already|exists|registered/i.test(error?.message ?? "");
    if (!taken) console.error("username-signup:", error);
    return json(taken ? 409 : 500, { error: taken ? "That username is taken" : "Couldn't create the account" });
  }

  // The profiles row may already exist from the auth.users trigger; either
  // way, make sure it carries the chosen name and never anything email-like.
  const { error: profileError } = await admin
    .from("profiles")
    .upsert({ id: created.user.id, username, display_name: displayName }, { onConflict: "id" });
  if (profileError) {
    console.error("username-signup profile:", profileError);
    await admin.auth.admin.deleteUser(created.user.id);
    return json(500, { error: "Couldn't create the account" });
  }

  const { error: joinError } = await admin
    .from("group_members")
    .insert({ group_id: group.id, user_id: created.user.id, role: "member" });
  if (joinError) {
    // The account works; they can still join with the code from the app.
    console.error("username-signup join:", joinError);
    return json(200, { ok: true, joined: false, recovery_code: password });
  }

  return json(200, { ok: true, joined: true, recovery_code: password });
});
