// Server only. No credentials, registration tokens or response bodies are logged.
import { JWT } from "npm:google-auth-library@10.3.0";

const DEVELOPMENT = "https://hijtwgugzzpjjkuutyfy.supabase.co";
const FIREBASE_PROJECT = "petal-quest-dev";
const approvedMessages = new Set([
  "Petal Quest: please check in",
  "Check on daughter — feeling pain",
]);

async function matchesSecret(actual: string, expected: string): Promise<boolean> {
  const encoder = new TextEncoder();
  const [a, b] = await Promise.all([
    crypto.subtle.digest("SHA-256", encoder.encode(actual)),
    crypto.subtle.digest("SHA-256", encoder.encode(expected)),
  ]);
  const left = new Uint8Array(a), right = new Uint8Array(b);
  let difference = 0;
  for (let i = 0; i < left.length; i++) difference |= left[i] ^ right[i];
  return difference === 0;
}

Deno.serve(async (request: Request) => {
  const reply = (status: number, value: object) => Response.json(value, { status });
  if (request.method !== "POST") return reply(405, { status: "method_not_allowed" });
  const workerSecret = Deno.env.get("PETAL_CHECKIN_WORKER_SECRET") || "";
  if (workerSecret.length < 32) return reply(503, { status: "not_configured" });
  if (!await matchesSecret(request.headers.get("x-petal-worker-key") || "", workerSecret)) {
    return reply(401, { status: "unauthorized" });
  }
  const base = Deno.env.get("SUPABASE_URL") || "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
  const accountJson = Deno.env.get("PETAL_FCM_SERVICE_ACCOUNT_JSON") || "";
  if (base !== DEVELOPMENT || !serviceKey || !accountJson) {
    return reply(503, { status: "not_configured" });
  }

  async function rpc(name: string, args: object) {
    const response = await fetch(`${base}/rest/v1/rpc/${name}`, {
      method: "POST", redirect: "error", signal: AbortSignal.timeout(15000),
      headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}`, "Content-Type": "application/json" },
      body: JSON.stringify(args),
    });
    if (!response.ok) throw new Error("RPC unavailable");
    return await response.json();
  }

  try {
    const account = JSON.parse(accountJson);
    if (account.project_id !== FIREBASE_PROJECT || account.type !== "service_account" ||
        typeof account.client_email !== "string" || typeof account.private_key !== "string") {
      return reply(503, { status: "not_configured" });
    }
    const client = new JWT({ email: account.client_email, key: account.private_key,
      scopes: ["https://www.googleapis.com/auth/firebase.messaging"] });
    const access = await client.getAccessToken();
    if (!access.token) return reply(503, { status: "push_unavailable" });
    const batch = await rpc("claim_high_pain_push", { p_limit: 5 });
    let completed = 0, retry = 0;
    for (const delivery of batch.deliveries || []) {
      let success = approvedMessages.has(delivery.push_text) &&
        Array.isArray(delivery.tokens) && delivery.tokens.length > 0;
      if (success) {
        for (const token of delivery.tokens) {
          if (typeof token !== "string" || token.length > 4096) { success = false; continue; }
          try {
            const response = await fetch(`https://fcm.googleapis.com/v1/projects/${FIREBASE_PROJECT}/messages:send`, {
              method: "POST", redirect: "error", signal: AbortSignal.timeout(15000),
              headers: { Authorization: `Bearer ${access.token}`, "Content-Type": "application/json" },
              body: JSON.stringify({ message: { token,
                // Data-only: the Parent receiver checks its current account
                // before showing anything, including after account switches.
                data: { kind: "parent_checkin", event_id: delivery.delivery_id,
                  recipient_user_id: delivery.recipient_user_id, checkin_text: delivery.push_text },
                android: { priority: "HIGH", ttl: "86400s", collapse_key: `checkin-${delivery.delivery_id}`,
                },
              } }),
            });
            // Invalid registration tokens are terminal for that destination. Other
            // destinations still receive the notice; no response body is logged.
            if (!response.ok) {
              let invalidToken = false;
              if (response.status === 404) {
                const errorBody = await response.json().catch(() => null);
                invalidToken = errorBody?.error?.details?.some((detail: { errorCode?: string; "@type"?: string }) =>
                  detail["@type"] === "type.googleapis.com/google.firebase.fcm.v1.FcmError" && detail.errorCode === "UNREGISTERED") === true;
              }
              if (!invalidToken) success = false;
            }
            await response.body?.cancel().catch(() => {});
          } catch { success = false; }
        }
      }
      const receipt = await rpc("complete_high_pain_push", {
        p_delivery_id: delivery.delivery_id, p_lease_id: delivery.lease_id, p_success: success,
      });
      if (success && receipt.status === "done") completed++; else retry++;
    }
    return reply(200, { status: "processed", completed, retry });
  } catch {
    return reply(503, { status: "push_unavailable" });
  }
});
