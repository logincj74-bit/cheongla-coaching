const fs = require("fs");
const vm = require("vm");
const assert = require("node:assert/strict");
const cp = require("child_process");
const typescriptPath = cp
  .execFileSync(
    "find",
    ["/home/agent/.npm/_npx", "-path", "*/typescript/lib/typescript.js"],
    { encoding: "utf8" },
  )
  .trim()
  .split("\n")[0];
if (!typescriptPath)
  throw Error("Install TypeScript before running this check");
const ts = require(typescriptPath);
const source = fs.readFileSync(
  "supabase/functions/cheongla-score-extract/index.ts",
  "utf8",
);
const js = ts.transpileModule(source.replace(/^import[^\n]*\n/, ""), {
  compilerOptions: {
    target: ts.ScriptTarget.ES2022,
    module: ts.ModuleKind.None,
  },
}).outputText;
let handler,
  role = "owner",
  approved = true,
  key = "test-key",
  verified = true,
  quotaError = false,
  fetchError = false,
  apiStatus = 200,
  output,
  requests = [];
const client = {
  auth: {
    getUser: async () => ({
      error: verified ? null : Error("invalid"),
      data: { user: verified ? { id: "test" } : null },
    }),
  },
  from: () => ({
    select: () => ({
      eq: () => ({
        single: async () => ({
          data: {
            role,
            approval_status: approved ? "approved" : "pending",
            membership_state: "active",
          },
        }),
      }),
    }),
  }),
  rpc: async () => ({ error: quotaError ? Error("quota") : null }),
};
const context = vm.createContext({
  Response,
  Request,
  AbortSignal,
  URL,
  console,
  Deno: {
    env: { get: (name) => (name === "OPENAI_API_KEY" ? key : "test-config") },
    serve: (fn) => (handler = fn),
  },
  createClient: () => client,
  fetch: async (url, args) => {
    requests.push({ url, args });
    if (fetchError) throw Error("network");
    return new Response(
      JSON.stringify({
        output: [
          {
            content: [
              {
                type: "output_text",
                text:
                  typeof output === "string" ? output : JSON.stringify(output),
              },
            ],
          },
        ],
      }),
      { status: apiStatus },
    );
  },
});
vm.runInContext(js, context);
const call = async (
  body = { image: "data:image/jpeg;base64,YWJj" },
  headers = {},
) =>
  handler(
    new Request("https://example.invalid/", {
      method: "POST",
      headers: {
        origin: "https://logincj74-bit.github.io",
        authorization: "Bearer test",
        "content-type": "application/json",
        ...headers,
      },
      body: JSON.stringify(body),
    }),
  );
(async () => {
  for (const name of ["student", "parent", "manager"]) {
    role = name;
    assert.equal((await call()).status, 403);
  }
  role = "owner";
  verified = false;
  assert.equal((await call()).status, 401);
  verified = true;
  key = "";
  assert.equal((await call()).status, 503);
  assert.equal(requests.length, 0);
  key = "test-key";
  assert.equal(
    (await call({}, { origin: "https://untrusted.invalid" })).status,
    405,
  );
  assert.equal(
    (await call({ image: "https://untrusted.invalid/report.jpg" })).status,
    400,
  );
  quotaError = true;
  assert.equal((await call()).status, 429);
  quotaError = false;
  assert.equal(requests.length, 0);
  output = {
    scores: [
      {
        subject: "국어",
        raw: 83,
        standard: 124,
        percentile: 88.5,
        grade: 3,
        student_name: "must be discarded",
      },
    ],
    student_name: "must be discarded",
  };
  const response = await call();
  assert.equal(response.status, 200);
  const result = await response.json();
  assert.equal(result.scores[0].percentile, 88.5);
  assert(!JSON.stringify(result).includes("must be discarded"));
  const sent = JSON.parse(requests[0].args.body);
  assert.equal(sent.store, false);
  assert.equal(sent.text.format.type, "json_schema");
  assert(!requests[0].url.includes("image"));
  output = {
    scores: [
      {
        subject: "수학",
        raw: null,
        standard: 129,
        percentile: null,
        grade: null,
      },
    ],
  };
  assert.equal((await (await call()).json()).scores[0].raw, null);
  output = {
    scores: [
      {
        subject: "수학(나형)",
        raw: null,
        standard: 118,
        percentile: 74,
        grade: 4,
      },
      {
        subject: "영어",
        raw: null,
        standard: null,
        percentile: null,
        grade: 3,
      },
      {
        subject: "미응시 과목",
        raw: null,
        standard: null,
        percentile: null,
        grade: null,
      },
    ],
  };
  const partial = await (await call()).json();
  assert.equal(partial.scores.length, 2);
  assert.equal(partial.scores[0].subject, "수학(나형)");
  assert.equal(partial.scores[1].standard, null);
  output = {
    scores: [
      { subject: "국어", raw: 80, standard: 120, percentile: 85, grade: 3 },
    ],
  };
  assert.equal(
    (await call({ image: "data:image/jpeg;base64,YWJj", exam_type: "csat" }))
      .status,
    502,
  );
  output = {
    scores: [
      {
        subject: "영어",
        raw: null,
        standard: null,
        percentile: null,
        grade: 2,
      },
    ],
  };
  const csatResponse = await call({
    image: "data:image/jpeg;base64,YWJj",
    exam_type: "csat",
  });
  assert.equal(csatResponse.status, 200);
  assert.equal((await csatResponse.json()).scores[0].raw, null);
  assert.equal(
    (await call({ image: "data:image/jpeg;base64,YWJj", exam_type: "unknown" }))
      .status,
    400,
  );
  for (const [field, value] of [
    ["raw", 101],
    ["grade", 0],
    ["grade", 10],
    ["grade", 1.5],
    ["standard", 201],
    ["percentile", "88"],
  ]) {
    output = { scores: [{ subject: "국어", [field]: value }] };
    assert.equal((await call()).status, 502);
  }
  output = "unreadable";
  assert.equal((await call()).status, 502);
  apiStatus = 429;
  assert.equal((await call()).status, 502);
  apiStatus = 200;
  fetchError = true;
  assert.equal((await call()).status, 502);
  console.log(
    "PASS OCR authorization, missing configuration, upload validation, quota, structured provider request, output allowlist, unknown score retention and failure handling; provider calls are mocked",
  );
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
