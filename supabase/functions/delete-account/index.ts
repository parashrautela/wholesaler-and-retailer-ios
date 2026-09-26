import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") return new Response("Method not allowed", { status: 405 });
  const authorization = request.headers.get("Authorization");
  if (!authorization) return Response.json({ error: "Authentication required" }, { status: 401 });

  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anonKey || !serviceKey) return Response.json({ error: "Server configuration error" }, { status: 500 });

  const token = authorization.replace(/^Bearer\s+/i, "").trim();
  if (!token) return Response.json({ error: "Authentication required" }, { status: 401 });
  const caller = createClient(url, anonKey);
  const admin = createClient(url, serviceKey);
  // Verify the presented access token explicitly. This remains the auth gate
  // when the Edge gateway's legacy JWT verification is disabled in config.
  const { data: { user }, error: authError } = await caller.auth.getUser(token);
  if (authError || !user) return Response.json({ error: "Invalid session" }, { status: 401 });

  try {
    // Delete owned cloud objects before the Auth row, so a storage failure
    // leaves the account intact and the user can retry.
    let role = user.user_metadata?.role;
    if (typeof role !== "string") {
      const { data: profile, error: profileError } = await admin.from("profiles")
        .select("role").eq("id", user.id).maybeSingle();
      if (profileError) throw profileError;
      role = profile?.role;
    }
    // Some older accounts lack role metadata and a profiles row.
    if (typeof role !== "string") {
      const { data: wholesaler, error: wholesalerError } = await admin.from("wholesalers")
        .select("user_id").eq("user_id", user.id).maybeSingle();
      if (wholesalerError) throw wholesalerError;
      if (wholesaler) role = "wholesaler";
    }
    if (typeof role !== "string") {
      const { data: retailer, error: retailerError } = await admin.from("retailers")
        .select("user_id").eq("user_id", user.id).maybeSingle();
      if (retailerError) throw retailerError;
      if (retailer) role = "retailer";
    }
    if (role === "wholesaler") {
      const { data: rows, error } = await admin.from("products")
        .select("raw_image_url,processed_image_url,image_url,generated_image_urls,custom_image_urls")
        .eq("wholesaler_id", user.id);
      if (error) throw error;
      const paths = new Set<string>();
      for (const row of rows ?? []) {
        const urls = [row.raw_image_url, row.processed_image_url, row.image_url,
          ...(row.generated_image_urls ?? []), ...(row.custom_image_urls ?? [])];
        for (const raw of urls) {
          if (typeof raw !== "string") continue;
          const marker = "/storage/v1/object/public/plant-images/";
          const index = raw.indexOf(marker);
          if (index >= 0) paths.add(decodeURIComponent(raw.slice(index + marker.length).split("?")[0]));
        }
      }
      if (paths.size) {
        const { error: storageError } = await admin.storage.from("plant-images").remove([...paths]);
        if (storageError) throw storageError;
      }
    }
    if (role === "retailer") {
      const { data: retailer, error: retailerError } = await admin.from("retailers")
        .select("id").eq("user_id", user.id).maybeSingle();
      if (retailerError) throw retailerError;
      if (retailer?.id) {
        const { data: designs, error: designsError } = await admin.from("retailer_designs")
          .select("image_url,image_urls").eq("retailer_id", retailer.id);
        if (designsError) throw designsError;
        const paths = new Set<string>();
        for (const design of designs ?? []) {
          for (const raw of [design.image_url, ...(design.image_urls ?? [])]) {
            if (typeof raw !== "string") continue;
            const marker = "/storage/v1/object/public/retailer-designs/";
            const index = raw.indexOf(marker);
            if (index >= 0) paths.add(decodeURIComponent(raw.slice(index + marker.length).split("?")[0]));
          }
        }
        if (paths.size) {
          const { error: storageError } = await admin.storage.from("retailer-designs").remove([...paths]);
          if (storageError) throw storageError;
        }
      }
    }

    const { error: deleteError } = await admin.auth.admin.deleteUser(user.id);
    if (deleteError) throw deleteError;
    return Response.json({ success: true });
  } catch (error) {
    console.error("delete-account failed", error);
    const message = error instanceof Error ? error.message : String(error);
    return Response.json({ error: `Couldn't delete account data: ${message}` }, { status: 500 });
  }
});
