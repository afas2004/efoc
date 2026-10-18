// POST /functions/v1/delete-account
// Deletes the caller's account for good: everything in the database through
// the delete_my_account() SQL function, then their clip videos, thumbnails,
// avatar and exports from Storage (supabase/migrations/20261018_delete_account.sql).
//
// Deploy: npx supabase functions deploy delete-account --project-ref <ref> --use-api

import { createClient } from "jsr:@supabase/supabase-js@2";

const ORIGINS = [/^https:\/\/(www\.)?efoc\.party$/, /^http:\/\/localhost(:\d+)?$/, /^http:\/\/127\.0\.0\.1(:\d+)?$/];
const VIDEO_EXT = /\.(mp4|webm|mov)$/;

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

  const auth = req.headers.get("Authorization") ?? "";
  const url = Deno.env.get("SUPABASE_URL")!;
  const asUser = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: auth } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: me } = await asUser.auth.getUser();
  const uid = me?.user?.id;
  if (!uid) return json(401, { error: "Not signed in" });

  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // Note every file path first (the rows hold them), delete the rows in one
  // transaction, then the files. If the SQL fails nothing is lost; if a
  // file delete fails it's only logged, since nothing points at it any more.
  const remove = async (bucket: string, paths: string[]) => {
    for (let i = 0; i < paths.length; i += 100) {
      const { error } = await admin.storage.from(bucket).remove(paths.slice(i, i + 100));
      if (error) console.error(`delete-account ${bucket}:`, error);
    }
  };

  const { data: clips } = await admin.from("clips").select("storage_path").eq("user_id", uid);
  const clipPaths = (clips ?? []).map((c) => c.storage_path as string).filter(Boolean);
  const { data: avatars } = await admin.storage.from("avatars").list(uid);
  const avatarPaths = (avatars ?? []).map((f) => `${uid}/${f.name}`);
  const { data: exports } = await admin.from("exports").select("storage_path").eq("user_id", uid);
  const exportPaths = (exports ?? []).map((e) => e.storage_path as string).filter(Boolean);

  const { error } = await asUser.rpc("delete_my_account");
  if (error) {
    console.error("delete-account rpc:", error);
    return json(500, { error: "Couldn't delete the account" });
  }

  await remove("clips", clipPaths);
  await remove("thumbnails", clipPaths.map((p) => p.replace(VIDEO_EXT, ".jpg")));
  await remove("avatars", avatarPaths);
  await remove("exports", exportPaths);

  return json(200, { ok: true });
});
