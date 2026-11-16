// The last submenu now uses the reviewed 2022 library. Legacy student/public tests
// predated the principal/manager role release; cover the new integration instead.
const fs=require('fs'),vm=require('vm'),assert=require('node:assert/strict'),{JSDOM}=require('jsdom');
const html=fs.readFileSync('index.html','utf8'),dom=new JSDOM(html),d=dom.window.document;
assert(d.querySelector('[data-mbti-page="mbti_study"] #mbtiLibraryRoot'));
assert(d.querySelector('#mbtiLegacyStudy').hidden,'legacy 2015 content remains visible');
for(const key of ['mbti_intro','mbti_groups','mbti_parents'])assert(d.querySelector('[data-mbti-page="'+key+'"]'));
assert(d.querySelector('script[src="mbti-library.js?v=2"]'));
for(const script of d.querySelectorAll('script:not([src])'))if(!script.type||script.type==='text/javascript')new vm.Script(script.textContent);
assert(html.includes("globalThis.CheonglaMBTILibraryUI?.open()"));assert(html.includes("referenceSections:code=>globalThis.CheonglaMBTILibraryUI?.references(code)"));
const policy=html.match(/function canUseMBTIStudy\(\)\{([^}]+)\}/)[1];assert(policy.includes("['owner','english_director','math_director','manager']"));
dom.window.close();console.log('PASS revised library integration: last submenu host, hidden legacy content, first three pages retained, current role scope, 2022 prescription references and inline script syntax');
require('./mbti-library-ui.cjs');
