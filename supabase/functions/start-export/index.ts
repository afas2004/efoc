// start-export: begins an on-demand vlog ("Make a vlog" in the app).
//
// The app inserts an exports row (RLS checks the Logs are yours), then
// calls this with { export_id }. We confirm the row is the caller's and
// still queued, then start .github/workflows/export.yml. The GitHub token
// lives only here, as the GITHUB_DISPATCH_TOKEN secret.
//
// Deploy: npx supabase functions deploy start-export --project-ref <ref> --use-api
// Secret: npx supabase secrets set GITHUB_DISPATCH_TOKEN=<token> --project-ref <ref>

import { createClient } from "jsr:@supabase/supabase-js@2";

const REPO = Deno.env.get("GITHUB_REPO") ?? "afas2004/efoc";
const MAX_ACTIVE = 2; // per person: queued + running

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function reply(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return reply(405, { error: "POST only" });

  const auth = req.headers.get("Authorization") ?? "";
  const url = Deno.env.get("SUPABASE_URL")!;
  const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const token = Deno.env.get("GITHUB_DISPATCH_TOKEN");
  if (!token) return reply(500, { error: "GITHUB_DISPATCH_TOKEN is not set" });

  let exportId: string | undefined;
  try {
    exportId = (await req.json())?.export_id;
  } catch {
    // fall through
  }
  if (!exportId) return reply(400, { error: "export_id is required" });

  // As the caller: RLS only shows their own rows.
  const asUser = createClient(url, anon, { global: { headers: { Authorization: auth } } });
  const { data: user } = await asUser.auth.getUser();
  if (!user?.user) return reply(401, { error: "Not signed in" });

  const { data: row } = await asUser
    .from("exports")
    .select("id, status")
    .eq("id", exportId)
    .maybeSingle();
  if (!row) return reply(404, { error: "Export not found" });
  if (row.status !== "queued") return reply(409, { error: `Export is ${row.status}` });

  const admin = createClient(url, service);
  const since = new Date(Date.now() - 15 * 60 * 1000).toISOString();
  const { count } = await admin
    .from("exports")
    .select("id", { count: "exact", head: true })
    .eq("user_id", user.user.id)
    .in("status", ["queued", "running"])
    .gte("created_at", since);
  if ((count ?? 0) > MAX_ACTIVE) {
    await admin.from("exports").update({ status: "failed", error: "Too many at once" })
      .eq("id", exportId);
    return reply(429, { error: "Wait for your other vlogs to finish first" });
  }

  const gh = await fetch(
    `https://api.github.com/repos/${REPO}/actions/workflows/export.yml/dispatches`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        Accept: "application/vnd.github+json",
        "Content-Type": "application/json",
        "User-Agent": "efoc-start-export",
      },
      body: JSON.stringify({ ref: "main", inputs: { export_id: exportId } }),
    },
  );
  if (!gh.ok) {
    const detail = (await gh.text()).slice(0, 200);
    await admin.from("exports").update({
      status: "failed",
      error: `Couldn't start (GitHub ${gh.status})`,
    }).eq("id", exportId);
    return reply(502, { error: `GitHub ${gh.status}`, detail });
  }

  return reply(200, { ok: true });
});
