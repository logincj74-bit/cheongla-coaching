Deno.serve((request: Request) => {
  if (request.method !== "GET") return new Response(null, { status: 405 });
  const ready = Boolean(Deno.env.get("OPENAI_API_KEY"));
  return new Response(JSON.stringify({ ready }), {
    status: ready ? 200 : 503,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });
});
