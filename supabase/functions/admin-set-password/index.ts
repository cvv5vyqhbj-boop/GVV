// Edge Function: admin-set-password
// Permite que pastor/super_admin defina uma nova senha para qualquer usuário.
// Segurança: valida o JWT do chamador e confere no banco que o papel dele
// esta na whitelist antes de usar a service_role.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "content-type": "application/json" },
  });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);

  const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
  const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

  const authHeader = req.headers.get("Authorization") || "";
  if (!authHeader.startsWith("Bearer ")) return json({ error: "sem token" }, 401);

  // Identifica o chamador
  const caller = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userErr } = await caller.auth.getUser();
  if (userErr || !userData?.user) return json({ error: "token invalido" }, 401);

  // Confirma papel do chamador
  const admin = createClient(SUPABASE_URL, SERVICE_ROLE);
  const { data: profile, error: profErr } = await admin
    .from("profiles")
    .select("role, active")
    .eq("user_id", userData.user.id)
    .single();
  if (profErr || !profile) return json({ error: "perfil nao encontrado" }, 403);
  if (!profile.active) return json({ error: "conta inativa" }, 403);
  if (!["super_admin", "pastor"].includes(profile.role)) {
    return json({ error: "sem permissao" }, 403);
  }

  // Payload
  let body: { user_id?: string; new_password?: string };
  try { body = await req.json(); } catch { return json({ error: "json invalido" }, 400); }
  const { user_id, new_password } = body || {};
  if (!user_id) return json({ error: "user_id obrigatorio" }, 400);
  if (!new_password || new_password.length < 6) {
    return json({ error: "senha precisa ter no minimo 6 caracteres" }, 400);
  }

  // Troca a senha
  const { error: updErr } = await admin.auth.admin.updateUserById(user_id, {
    password: new_password,
  });
  if (updErr) return json({ error: updErr.message }, 500);

  return json({ ok: true });
});
