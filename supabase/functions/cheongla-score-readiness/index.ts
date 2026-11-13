// Probe model access only: no images, generated responses, keys or provider bodies are returned.
let cachedKey = "";
let checkedUntil = 0;
let pending: Promise<{ provider_ready: boolean; provider_status: number | null; provider_error: string | null }> | null = null;
async function provider(key: string) {
  if (cachedKey !== key || Date.now() >= checkedUntil || !pending) {
    cachedKey = key;
    checkedUntil = Date.now() + 60000;
    pending = (async () => {
      try {
        const model = Deno.env.get("SCORE_OCR_MODEL") || "gpt-4.1-mini";
        const response = await fetch("https://api.openai.com/v1/models/" + encodeURIComponent(model), {
          headers: { Authorization: "Bearer " + key },
          signal: AbortSignal.timeout(10000),
        });
        response.body?.cancel().catch(()=>{});
        return { provider_ready: response.ok, provider_status: response.status, provider_error: null };
      } catch (error) {
        return { provider_ready: false, provider_status: null, provider_error: error instanceof Error ? error.name : "UnknownError" };
      }
    })();
  }
  return pending;
}
Deno.serve(async (request: Request) => {
  if (request.method !== "GET") return new Response(null, { status: 405 });
  const key = (Deno.env.get("OPENAI_API_KEY") || "").trim();
  const key_format_valid = /^sk-\S+$/.test(key);
  const status = key ? await provider(key) : { provider_ready: false, provider_status: null, provider_error: null };
  return new Response(JSON.stringify({ ready: Boolean(key), key_format_valid, ...status }), {
    status: key && status.provider_ready ? 200 : 503,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
});
