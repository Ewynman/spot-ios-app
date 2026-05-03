import "jsr:@supabase/functions-js/edge-runtime.d.ts";
// Resolved via `deno.json` `imports` (Deno / Supabase Edge — not Node).
import { createClient, type User } from "@supabase/supabase-js";

type MediaKind = "spot_image" | "profile_image";
type MediaStatus =
  | "pending"
  | "approved"
  | "rejected"
  | "failed"
  | "deleted"
  | "legacy_unmoderated";

interface MediaAssetRow {
  id: string;
  owner_id: string;
  kind: MediaKind;
  status: MediaStatus;
  pending_bucket: string | null;
  pending_path: string | null;
  approved_bucket: string | null;
  approved_path: string | null;
}

interface ThresholdRow {
  sexualBlockAt: number;
  violenceBlockAt: number;
  hateBlockAt: number;
  selfHarmBlockAt: number;
}

const DEFAULT_THRESHOLDS: Record<MediaKind, ThresholdRow> = {
  spot_image: {
    sexualBlockAt: 4,
    violenceBlockAt: 4,
    hateBlockAt: 4,
    selfHarmBlockAt: 4,
  },
  profile_image: {
    sexualBlockAt: 2,
    violenceBlockAt: 4,
    hateBlockAt: 4,
    selfHarmBlockAt: 4,
  },
};

const MAX_BYTES = 4 * 1024 * 1024;
const ALLOWED_MIME = new Set(["image/jpeg", "image/png", "image/webp"]);

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Connection": "keep-alive",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Headers":
        "authorization, x-client-info, apikey, content-type",
    },
  });
}

function parseThresholds(): Record<MediaKind, ThresholdRow> {
  const raw = Deno.env.get("MODERATION_THRESHOLDS_JSON");
  if (!raw) return DEFAULT_THRESHOLDS;
  try {
    const parsed = JSON.parse(raw) as Record<string, Partial<ThresholdRow>>;
    const out: Record<MediaKind, ThresholdRow> = { ...DEFAULT_THRESHOLDS };
    for (const k of ["spot_image", "profile_image"] as MediaKind[]) {
      const p = parsed[k];
      if (!p) continue;
      out[k] = {
        sexualBlockAt: p.sexualBlockAt ?? DEFAULT_THRESHOLDS[k].sexualBlockAt,
        violenceBlockAt: p.violenceBlockAt ?? DEFAULT_THRESHOLDS[k].violenceBlockAt,
        hateBlockAt: p.hateBlockAt ?? DEFAULT_THRESHOLDS[k].hateBlockAt,
        selfHarmBlockAt: p.selfHarmBlockAt ?? DEFAULT_THRESHOLDS[k].selfHarmBlockAt,
      };
    }
    return out;
  } catch {
    return DEFAULT_THRESHOLDS;
  }
}

function normalizeAzureScores(
  categoriesAnalysis: Array<{ category?: string; severity?: number }>,
): Record<"hate" | "selfHarm" | "sexual" | "violence", number> {
  const scores = {
    hate: 0,
    selfHarm: 0,
    sexual: 0,
    violence: 0,
  };
  for (const row of categoriesAnalysis ?? []) {
    const c = (row.category ?? "").toLowerCase();
    const sev = typeof row.severity === "number" ? row.severity : 0;
    if (c === "hate") scores.hate = sev;
    else if (c === "selfharm" || c === "self_harm") scores.selfHarm = sev;
    else if (c === "sexual") scores.sexual = sev;
    else if (c === "violence") scores.violence = sev;
  }
  return scores;
}

function evaluateScores(kind: MediaKind, scores: Record<string, number>, thresholds: Record<MediaKind, ThresholdRow>): { ok: boolean; reason?: string } {
  const t = thresholds[kind];
  if (scores.sexual >= t.sexualBlockAt) return { ok: false, reason: "image_policy_rejected" };
  if (scores.violence >= t.violenceBlockAt) return { ok: false, reason: "image_policy_rejected" };
  if (scores.hate >= t.hateBlockAt) return { ok: false, reason: "image_policy_rejected" };
  if (scores.selfHarm >= t.selfHarmBlockAt) return { ok: false, reason: "image_policy_rejected" };
  return { ok: true };
}

function approvedBucketForKind(kind: MediaKind): string {
  return kind === "profile_image" ? "approved_profile_images" : "approved_spot_images";
}

async function requireUser(req: Request): Promise<{ user: User; token: string } | Response> {
  const auth = req.headers.get("Authorization");
  if (!auth?.startsWith("Bearer ")) {
    return jsonResponse({ error: "missing_authorization" }, 401);
  }
  const token = auth.slice("Bearer ".length).trim();
  const url = Deno.env.get("SUPABASE_URL")!;
  const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
  const userClient = createClient(url, anon, {
    global: { headers: { Authorization: `Bearer ${token}` } },
  });
  const { data, error } = await userClient.auth.getUser(token);
  if (error || !data.user) {
    return jsonResponse({ error: "invalid_token" }, 401);
  }
  return { user: data.user, token };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
        "Access-Control-Allow-Headers":
          "authorization, x-client-info, apikey, content-type",
      },
    });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }

  const userResult = await requireUser(req);
  if (userResult instanceof Response) return userResult;
  const { user } = userResult;

  let body: { mediaAssetId?: string };
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "invalid_json" }, 400);
  }
  const mediaAssetId = body.mediaAssetId?.trim();
  if (!mediaAssetId) {
    return jsonResponse({ error: "mediaAssetId_required" }, 400);
  }

  const url = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const admin = createClient(url, serviceKey);

  const thresholds = parseThresholds();

  const { data: asset, error: fetchErr } = await admin
    .from("media_assets")
    .select(
      "id,owner_id,kind,status,pending_bucket,pending_path,approved_bucket,approved_path",
    )
    .eq("id", mediaAssetId)
    .maybeSingle();

  if (fetchErr || !asset) {
    console.error("media_asset_fetch_failed", fetchErr?.message);
    return jsonResponse({ approved: false, mediaAssetId, reason: "moderation_unavailable", retryable: true }, 503);
  }

  const row = asset as MediaAssetRow;
  if (row.owner_id !== user.id) {
    return jsonResponse({ error: "forbidden" }, 403);
  }

  if (row.status === "approved" && row.approved_bucket && row.approved_path) {
    return jsonResponse({
      approved: true,
      mediaAssetId: row.id,
      approvedBucket: row.approved_bucket,
      approvedPath: row.approved_path,
    });
  }

  if (row.kind !== "spot_image" && row.kind !== "profile_image") {
    return jsonResponse({ error: "invalid_kind" }, 400);
  }

  if (row.status !== "pending" && row.status !== "failed") {
    return jsonResponse({ approved: false, mediaAssetId, reason: "invalid_state" }, 409);
  }

  if (!row.pending_bucket || !row.pending_path) {
    return jsonResponse({ approved: false, mediaAssetId, reason: "moderation_unavailable", retryable: false }, 422);
  }

  const { data: file, error: dlErr } = await admin.storage
    .from(row.pending_bucket)
    .download(row.pending_path);

  if (dlErr || !file) {
    console.error("pending_download_failed", dlErr?.message);
    await admin.from("media_assets").update({
      status: "failed",
      rejection_reason: "pending_download_failed",
      updated_at: new Date().toISOString(),
    }).eq("id", mediaAssetId);
    await admin.from("media_moderation_events").insert({
      media_asset_id: mediaAssetId,
      actor_user_id: user.id,
      status: "failed",
      scores: {},
      reason: "pending_download_failed",
      error_code: "storage_download",
    });
    return jsonResponse({ approved: false, mediaAssetId, reason: "moderation_unavailable", retryable: true }, 503);
  }

  const bytes = new Uint8Array(await file.arrayBuffer());
  if (bytes.byteLength < 32 || bytes.byteLength > MAX_BYTES) {
    await admin.storage.from(row.pending_bucket).remove([row.pending_path]);
    await admin.from("media_assets").update({
      status: "rejected",
      rejection_reason: "invalid_image_size",
      moderated_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    }).eq("id", mediaAssetId);
    await admin.from("media_moderation_events").insert({
      media_asset_id: mediaAssetId,
      actor_user_id: user.id,
      status: "rejected",
      scores: {},
      reason: "invalid_image_size",
    });
    return jsonResponse({ approved: false, mediaAssetId, reason: "image_policy_rejected" }, 422);
  }

  const mime = file.type && file.type !== "application/octet-stream"
    ? file.type
    : guessMime(bytes);
  if (!mime || !ALLOWED_MIME.has(mime)) {
    await admin.storage.from(row.pending_bucket).remove([row.pending_path]);
    await admin.from("media_assets").update({
      status: "rejected",
      rejection_reason: "unsupported_mime",
      mime_type: mime,
      byte_size: bytes.byteLength,
      moderated_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    }).eq("id", mediaAssetId);
    await admin.from("media_moderation_events").insert({
      media_asset_id: mediaAssetId,
      actor_user_id: user.id,
      status: "rejected",
      scores: {},
      reason: "unsupported_mime",
    });
    return jsonResponse({ approved: false, mediaAssetId, reason: "image_policy_rejected" }, 422);
  }

  const azureEndpoint = (Deno.env.get("AZURE_CONTENT_SAFETY_ENDPOINT") ?? "").replace(/\/+$/, "");
  const azureKey = Deno.env.get("AZURE_CONTENT_SAFETY_KEY") ?? "";
  const apiVersion = Deno.env.get("AZURE_CONTENT_SAFETY_API_VERSION") ?? "2024-09-01";

  if (!azureEndpoint || !azureKey) {
    console.error("azure_env_missing");
    await admin.from("media_assets").update({
      status: "failed",
      rejection_reason: "azure_config_missing",
      updated_at: new Date().toISOString(),
    }).eq("id", mediaAssetId);
    return jsonResponse({ approved: false, mediaAssetId, reason: "moderation_unavailable", retryable: true }, 503);
  }

  const b64 = bytesToBase64(bytes);
  const analyzeUrl =
    `${azureEndpoint}/contentsafety/image:analyze?api-version=${encodeURIComponent(apiVersion)}`;

  let azureJson: { categoriesAnalysis?: Array<{ category?: string; severity?: number }> };
  try {
    const azRes = await fetch(analyzeUrl, {
      method: "POST",
      headers: {
        "Ocp-Apim-Subscription-Key": azureKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        image: { content: b64 },
        categories: ["Hate", "SelfHarm", "Sexual", "Violence"],
        outputType: "FourSeverityLevels",
      }),
    });
    if (!azRes.ok) {
      console.error("azure_http_error", azRes.status);
      await admin.from("media_assets").update({
        status: "failed",
        rejection_reason: `azure_http_${azRes.status}`,
        updated_at: new Date().toISOString(),
      }).eq("id", mediaAssetId);
      await admin.from("media_moderation_events").insert({
        media_asset_id: mediaAssetId,
        actor_user_id: user.id,
        status: "failed",
        scores: {},
        error_code: `azure_${azRes.status}`,
        reason: "azure_error",
      });
      return jsonResponse({ approved: false, mediaAssetId, reason: "moderation_unavailable", retryable: azRes.status >= 500 },
        azRes.status >= 500 ? 503 : 422);
    }
    azureJson = await azRes.json();
  } catch (e) {
    console.error("azure_fetch_failed", (e as Error).message);
    await admin.from("media_assets").update({
      status: "failed",
      rejection_reason: "azure_network_error",
      updated_at: new Date().toISOString(),
    }).eq("id", mediaAssetId);
    await admin.from("media_moderation_events").insert({
      media_asset_id: mediaAssetId,
      actor_user_id: user.id,
      status: "failed",
      scores: {},
      error_code: "azure_network",
      reason: "azure_network_error",
    });
    return jsonResponse({ approved: false, mediaAssetId, reason: "moderation_unavailable", retryable: true }, 503);
  }

  const categories = Array.isArray(azureJson.categoriesAnalysis)
    ? azureJson.categoriesAnalysis
    : [];
  if (categories.length === 0) {
    await admin.from("media_assets").update({
      status: "failed",
      rejection_reason: "azure_malformed",
      updated_at: new Date().toISOString(),
    }).eq("id", mediaAssetId);
    await admin.from("media_moderation_events").insert({
      media_asset_id: mediaAssetId,
      actor_user_id: user.id,
      status: "failed",
      scores: {},
      reason: "azure_malformed",
    });
    return jsonResponse({ approved: false, mediaAssetId, reason: "moderation_unavailable", retryable: true }, 503);
  }

  const scores = normalizeAzureScores(categories);
  const decision = evaluateScores(row.kind, scores as Record<string, number>, thresholds);
  const scoresPayload = {
    hate: scores.hate,
    selfHarm: scores.selfHarm,
    sexual: scores.sexual,
    violence: scores.violence,
  };

  if (!decision.ok) {
    await admin.storage.from(row.pending_bucket).remove([row.pending_path]);
    await admin.from("media_assets").update({
      status: "rejected",
      scores: scoresPayload,
      azure_result: { categoriesAnalysis: categories.map((c) => ({ category: c.category, severity: c.severity })) },
      rejection_reason: decision.reason ?? "image_policy_rejected",
      mime_type: mime,
      byte_size: bytes.byteLength,
      moderated_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    }).eq("id", mediaAssetId);
    await admin.from("media_moderation_events").insert({
      media_asset_id: mediaAssetId,
      actor_user_id: user.id,
      status: "rejected",
      scores: scoresPayload,
      reason: decision.reason,
    });
    return jsonResponse({ approved: false, mediaAssetId, reason: "image_policy_rejected" }, 422);
  }

  const destBucket = approvedBucketForKind(row.kind);
  const ext = mime === "image/png" ? "png" : mime === "image/webp" ? "webp" : "jpg";
  const destPath = `${row.owner_id.toLowerCase()}/${row.id}.${ext}`;

  const { error: upErr } = await admin.storage.from(destBucket).upload(destPath, bytes, {
    contentType: mime,
    upsert: true,
  });
  if (upErr) {
    console.error("approved_upload_failed", upErr.message);
    await admin.from("media_assets").update({
      status: "failed",
      rejection_reason: "approved_upload_failed",
      updated_at: new Date().toISOString(),
    }).eq("id", mediaAssetId);
    await admin.from("media_moderation_events").insert({
      media_asset_id: mediaAssetId,
      actor_user_id: user.id,
      status: "failed",
      scores: scoresPayload,
      error_code: "approved_upload",
      reason: "approved_upload_failed",
    });
    return jsonResponse({ approved: false, mediaAssetId, reason: "moderation_unavailable", retryable: true }, 503);
  }

  await admin.storage.from(row.pending_bucket).remove([row.pending_path]);

  await admin.from("media_assets").update({
    status: "approved",
    scores: scoresPayload,
    azure_result: { categoriesAnalysis: categories.map((c) => ({ category: c.category, severity: c.severity })) },
    approved_bucket: destBucket,
    approved_path: destPath,
    pending_bucket: null,
    pending_path: null,
    mime_type: mime,
    byte_size: bytes.byteLength,
    moderated_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
  }).eq("id", mediaAssetId);

  await admin.from("media_moderation_events").insert({
    media_asset_id: mediaAssetId,
    actor_user_id: user.id,
    status: "approved",
    scores: scoresPayload,
  });

  return jsonResponse({
    approved: true,
    mediaAssetId: row.id,
    approvedBucket: destBucket,
    approvedPath: destPath,
  });
});

function bytesToBase64(bytes: Uint8Array): string {
  let binary = "";
  const chunkSize = 0x8000;
  for (let i = 0; i < bytes.length; i += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunkSize));
  }
  return btoa(binary);
}

function guessMime(bytes: Uint8Array): string {
  if (bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) return "image/jpeg";
  if (bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47) return "image/png";
  if (bytes[0] === 0x52 && bytes[1] === 0x49 && bytes[2] === 0x46 && bytes[3] === 0x46) return "image/webp";
  return "application/octet-stream";
}
