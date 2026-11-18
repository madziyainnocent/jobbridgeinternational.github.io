const cors = (origin, env) => ({
  "Access-Control-Allow-Origin": origin === env.ALLOWED_ORIGIN ? origin : env.ALLOWED_ORIGIN,
  "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
  "Vary": "Origin"
});

const json = (data, status = 200, headers = {}) =>
  new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", ...headers }
  });

async function askJobBridgeAI(message, env) {
  if (!env.OPENAI_API_KEY) throw new Error("AI service is not configured.");
  const instructions = `You are the JobBridge International recruitment assistant.
Answer politely and clearly using only the following verified public information:
- JobBridge International connects African talent with international employment opportunities.
- A featured vacancy is Truck Drivers – Lithuania.
- Applicants should have suitable heavy-vehicle driving licence, truck-driving experience, and willingness to complete recruitment and documentation checks.
- Selection, job offers, visas and migration approvals are not guaranteed.
- For official enquiries, direct candidates to placements@jobbridgeinternational.online.
Never invent vacancies, salaries, processing times, visa outcomes, or application statuses.
Never request passwords, payment card details, or sensitive identity documents in chat.
For a personal application status, ask the candidate to sign in to the secure candidate portal.
Do not claim an application is approved or selected unless an authenticated recruitment system confirms it.`;
  const response = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${env.OPENAI_API_KEY}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      model: env.OPENAI_MODEL || "gpt-5.4-mini",
      instructions,
      input: message,
      max_output_tokens: 450
    })
  });
  if (!response.ok) throw new Error("AI provider returned an error.");
  const result = await response.json();
  const answer = (result.output || [])
    .flatMap(item => item.content || [])
    .filter(item => item.type === "output_text")
    .map(item => item.text).join("\n").trim();
  return answer || "Please contact placements@jobbridgeinternational.online for assistance.";
}

async function sendWhatsApp(to, body, env) {
  if (!env.WHATSAPP_TOKEN || !env.WHATSAPP_PHONE_NUMBER_ID) return;
  const url = `https://graph.facebook.com/${env.META_GRAPH_VERSION || "v23.0"}/${env.WHATSAPP_PHONE_NUMBER_ID}/messages`;
  const response = await fetch(url, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${env.WHATSAPP_TOKEN}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      messaging_product: "whatsapp",
      recipient_type: "individual",
      to,
      type: "text",
      text: { preview_url: false, body }
    })
  });
  if (!response.ok) throw new Error("WhatsApp message could not be sent.");
}

async function verifyMetaSignature(request, rawBody, secret) {
  if (!secret) return false;
  const signature = request.headers.get("X-Hub-Signature-256") || "";
  if (!signature.startsWith("sha256=")) return false;
  const key = await crypto.subtle.importKey(
    "raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]
  );
  const digest = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(rawBody));
  const expected = "sha256=" + [...new Uint8Array(digest)].map(b => b.toString(16).padStart(2,"0")).join("");
  return signature.length === expected.length &&
    [...signature].reduce((acc, ch, i) => acc | (ch.charCodeAt(0) ^ expected.charCodeAt(i)), 0) === 0;
}

export default {
  async fetch(request, env) {
    const origin = request.headers.get("Origin") || "";
    const headers = cors(origin, env);

    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers });
    const url = new URL(request.url);

    if (url.pathname === "/api/health" && request.method === "GET") {
      return json({ service: "JobBridge API", status: "online" }, 200, headers);
    }

    if (url.pathname === "/api/chat" && request.method === "POST") {
      if (origin !== env.ALLOWED_ORIGIN) return json({ error: "Origin not allowed." }, 403, headers);
      try {
        const body = await request.json();
        const message = String(body.message || "").trim();
        if (!message || message.length > 2000) return json({ error: "Enter a message up to 2,000 characters." }, 400, headers);
        const answer = await askJobBridgeAI(message, env);
        return json({ answer }, 200, headers);
      } catch (error) {
        return json({ error: "The assistant is temporarily unavailable. Please email placements@jobbridgeinternational.online." }, 503, headers);
      }
    }

    if (url.pathname === "/webhooks/whatsapp" && request.method === "GET") {
      const mode = url.searchParams.get("hub.mode");
      const token = url.searchParams.get("hub.verify_token");
      const challenge = url.searchParams.get("hub.challenge");
      if (mode === "subscribe" && token && token === env.WHATSAPP_VERIFY_TOKEN) {
        return new Response(challenge || "", { status: 200 });
      }
      return new Response("Forbidden", { status: 403 });
    }

    if (url.pathname === "/webhooks/whatsapp" && request.method === "POST") {
      const raw = await request.text();
      if (!await verifyMetaSignature(request, raw, env.META_APP_SECRET)) {
        return new Response("Invalid signature", { status: 401 });
      }
      try {
        const payload = JSON.parse(raw);
        const entries = payload.entry || [];
        for (const entry of entries) {
          for (const change of entry.changes || []) {
            const value = change.value || {};
            for (const message of value.messages || []) {
              if (message.type !== "text" || !message.from || !message.text?.body) continue;
              const answer = await askJobBridgeAI(message.text.body, env);
              await sendWhatsApp(message.from, answer, env);
            }
          }
        }
      } catch (error) {
        return new Response("Webhook processing failed", { status: 500 });
      }
      return new Response("EVENT_RECEIVED", { status: 200 });
    }

    return json({ error: "Not found" }, 404, headers);
  }
};
