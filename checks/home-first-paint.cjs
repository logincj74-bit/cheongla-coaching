const assert = require('node:assert/strict');
const fs = require('node:fs');
const { JSDOM } = require('jsdom');

const html = fs.readFileSync('index.html', 'utf8');
const startup = html.slice(
 html.indexOf("document.documentElement.setAttribute('data-home-starting'"),
 html.indexOf('</script>', html.indexOf('function finishHomeStartup'))
);
const restore = html.slice(
 html.indexOf('async function restoreInitialView()'),
 html.indexOf('</script>', html.indexOf('async function restoreInitialView()'))
);

async function check(hasSession) {
 const { window } = new JSDOM(html, { runScripts: 'outside-only', url: 'https://app.example/' });
 try {
  const document = window.document;
  const $ = id => document.getElementById(id);
  let releaseSession;
  const session = new Promise(resolve => { releaseSession = resolve; });
  const ready = new Promise(resolve => window.addEventListener('cheongla:home-ready', resolve, { once: true }));
  const requests = { getSession: 0, loadProfile: 0 };
  window.CheonglaHomeModulesReady = new Promise(() => {});
  window.eval('var manualAuthStarted=false,restoringInitialSession=false,initialProfileLoad=null,contactNeedsPhone=false,publicPages={};');
  Object.assign(window, {
   $,
   consumePushArrival: () => '',
   getClient: async () => ({ auth: { getSession: () => { requests.getSession++; return session; } } }),
   loadProfile: async (_, options) => { requests.loadProfile++; assert.equal(options.startup, true); },
   updateHomeAccount: () => { $('memberEntryLabel').textContent = '내 계정 · 학원 서비스'; }
  });

  window.eval(startup);
  window.eval(restore);
  assert(document.documentElement.hasAttribute('data-home-starting'));
  assert(!document.body.textContent.includes('청라 홈을 준비하고 있습니다'));
  assert.notEqual(window.getComputedStyle(document.querySelector('.home-today')).display, 'none');
  assert.notEqual(window.getComputedStyle($('homePanel')).display, 'none');
  assert($('homePanel').hasAttribute('inert'));
  assert.equal(window.getComputedStyle($('openMemberArea')).visibility, 'hidden');
  assert($('authPanel').hidden);

  releaseSession({ data: { session: hasSession ? {} : null } });
  let timeout;
  try {
   await Promise.race([ready, new Promise((_, reject) => { timeout = setTimeout(() => reject(new Error('Home waited for optional modules')), 450); })]);
  } finally {
   clearTimeout(timeout);
  }
  assert(!document.documentElement.hasAttribute('data-home-starting'));
  assert(!document.querySelector('[data-startup-lock][inert]'));
  assert.equal(window.getComputedStyle($('openMemberArea')).visibility, 'visible');
  assert.equal(requests.getSession, 1);
  assert.equal(requests.loadProfile, Number(hasSession));
  assert.equal($('memberEntryLabel').textContent, hasSession ? '내 계정 · 학원 서비스' : '로그인하기');
  assert($('authPanel').hidden);
 } finally {
  window.close();
 }
}

(async () => {
 await check(true);
 await check(false);
 console.log('PASS first paint: visible home while session is pending, no login flash, no optional module wait, signed-in and guest home');
})().catch(error => { console.error(error); process.exitCode = 1; });
