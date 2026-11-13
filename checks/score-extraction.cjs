const fs = require("fs");
const vm = require("vm");
const assert = require("node:assert/strict");
const { stripTypeScriptTypes } = require("node:module");
const source = fs.readFileSync("supabase/functions/cheongla-score-extract/index.ts", "utf8");
const js = stripTypeScriptTypes(source.replace(/^import[^\n]*\n/, ""));
let handler,
  role = "owner",
  approved = true,
  key = "test-key",
  verified = true,
  quotaError = false,
  fetchError = false,
  apiStatus = 200,
  providerCode = "",
  providerType = "",
  diagnosticLogs = [],
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
const globals = {
  Response,
  Request,
  AbortSignal,
  URL,
  console: {...console, warn: message=>diagnosticLogs.push(message)},
  Deno: {
    env: { get: (name) => (name === "OPENAI_API_KEY" ? key : "test-config") },
    serve: (fn) => (handler = fn),
  },
  createClient: () => client,
  fetch: async (url, args) => {
    requests.push({ url, args });
    if (fetchError) throw Error("network");
    return new Response(
      JSON.stringify(apiStatus >= 400 ? {error:{code:providerCode,type:providerType,message:"provider-private-detail-test-key"}} : {
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
};
vm.runInContext(js, vm.createContext(globals));
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
  const paused = await call();
  assert.equal(paused.status,503);
  assert.equal((await paused.json()).code,"ocr_paused");
  assert.equal(requests.length,0,"paused server called paid provider");
  // Exercise retained extraction logic with a test-only switch in a separate VM.
  vm.runInContext(js.replace("const photoRecognitionEnabled = false", "const photoRecognitionEnabled = true"), vm.createContext({...globals}));
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
  assert.equal((await call()).status, 429);
  providerCode="insufficient_quota";
  const credit=await call();assert.equal(credit.status,402);const creditBody=await credit.json();assert.equal(creditBody.code,'api_credit');assert(creditBody.error.includes('잔액'));assert(!JSON.stringify(creditBody).includes('provider-private-detail'));
  for(const [code,expected,http] of [['credit_balance_exhausted','api_credit',402],['organization_usage_limit_exceeded','api_usage_limit',403],['organization_spend_limit_exceeded','api_org_budget',402],['project_spend_limit_exceeded','api_project_budget',402],['slow_down','api_rate_limit',429]]){providerCode=code;const response=await call();assert.equal(response.status,http);assert.equal((await response.json()).code,expected);}
  providerCode='new_unknown_code';providerType='insufficient_quota';const quotaFallback=await call();assert.equal(quotaFallback.status,402);assert.equal((await quotaFallback.json()).code,'api_credit');providerType='';const unknownLimit=await call();assert.equal(unknownLimit.status,429);const unknownBody=await unknownLimit.json();assert.equal(unknownBody.code,'api_request_limit');assert(!unknownBody.error.includes('잠시 기다린'));
  for(const [status,code,expected,http] of [[401,'invalid_api_key','api_key',503],[403,'permission_denied','api_permission',503],[404,'model_not_found','api_model',503],[400,'invalid_image','image_format',422],[400,'invalid_json_schema','api_request',502]]){apiStatus=status;providerCode=code;const response=await call();assert.equal(response.status,http);assert.equal((await response.json()).code,expected);}
  assert(!diagnosticLogs.join('').includes('provider-private-detail'));assert(!diagnosticLogs.join('').includes('test-key'));
  apiStatus = 200;
  fetchError = true;
  assert.equal((await call()).status, 502);
  console.log(
    "PASS OCR authorization, missing configuration, upload validation, quota, structured provider request, output allowlist, unknown score retention, credit/auth/permission/rate/image error categories and sanitized diagnostic logs; provider calls are mocked",
  );
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
