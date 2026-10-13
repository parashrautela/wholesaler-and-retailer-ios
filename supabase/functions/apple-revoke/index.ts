import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { importPKCS8, SignJWT } from "https://esm.sh/jose@5.9.6";

// Revokes the caller's Sign in with Apple tokens before their account is
// deleted, as App Review requires for apps offering Sign in with Apple. The app
// asks Apple for a fresh authorization code just before deletion; this
// exchanges it for a refresh token and revokes that, which ends the app's
// access in the user's Apple ID settings.
//
// Secrets (Supabase → Edge Functions → Secrets):
//   APPLE_TEAM_ID          J3BH2RPA7Y
//   APPLE_SIGNIN_KEY_ID    the Key ID of a "Sign in with Apple" key
//   APPLE_SIGNIN_KEY       that key's .p8 contents (PEM, including BEGIN/END lines)
//   APPLE_CLIENT_ID        com.jewelindia.app (optional; this is the default)

async function clientSecret(teamID: string, keyID: string, pem: string, clientID: string) {
  const key = await importPKCS8(pem.replace(/\\n/g, "\n"), "ES256");
  return await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: keyID })
    .setIssuer(teamID)
    .setIssuedAt()
    .setExpirationTime("5m")
    .setAudience("https://appleid.apple.com")
    .setSubject(clientID)
    .sign(key);
}

async function appleForm(path: string, fields: Record<string, string>) {
  return await fetch(`https://appleid.apple.com/auth/${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams(fields),
  });
}

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") return new Response("Method not allowed", { status: 405 });

  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const teamID = Deno.env.get("APPLE_TEAM_ID");
  const keyID = Deno.env.get("APPLE_SIGNIN_KEY_ID");
  const pem = Deno.env.get("APPLE_SIGNIN_KEY");
  const clientID = Deno.env.get("APPLE_CLIENT_ID") ?? "com.jewelindia.app";
  if (!url || !anonKey || !teamID || !keyID || !pem) {
    return Response.json({ error: "Server configuration error" }, { status: 500 });
  }

  const token = (request.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "").trim();
  if (!token) return Response.json({ error: "Authentication required" }, { status: 401 });
  const { data: { user }, error: authError } = await createClient(url, anonKey).auth.getUser(token);
  if (authError || !user) return Response.json({ error: "Invalid session" }, { status: 401 });

  let code: unknown;
  try {
    ({ code } = await request.json());
  } catch {
    return Response.json({ error: "Invalid body" }, { status: 400 });
  }
  if (typeof code !== "string" || code.length === 0) {
    return Response.json({ error: "Missing authorization code" }, { status: 400 });
  }

  try {
    const secret = await clientSecret(teamID, keyID, pem, clientID);
    const exchange = await appleForm("token", {
      grant_type: "authorization_code",
      code,
      client_id: clientID,
      client_secret: secret,
    });
    const tokens = await exchange.json().catch(() => ({}));
    const refreshToken = tokens.refresh_token as string | undefined;
    const accessToken = tokens.access_token as string | undefined;
    if (!exchange.ok || (!refreshToken && !accessToken)) {
      console.error("apple-revoke: code exchange failed", user.id, exchange.status, tokens.error);
      return Response.json({ error: "Apple code exchange failed" }, { status: 502 });
    }

    const revoke = await appleForm("revoke", {
      client_id: clientID,
      client_secret: secret,
      token: refreshToken ?? accessToken!,
      token_type_hint: refreshToken ? "refresh_token" : "access_token",
    });
    if (!revoke.ok) {
      console.error("apple-revoke: revoke failed", user.id, revoke.status);
      return Response.json({ error: "Apple revoke failed" }, { status: 502 });
    }
    return Response.json({ ok: true });
  } catch (error) {
    console.error("apple-revoke: unexpected error", user.id, error);
    return Response.json({ error: "Apple revoke failed" }, { status: 500 });
  }
});
