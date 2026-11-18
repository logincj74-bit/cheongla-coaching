const fs=require('node:fs'),assert=require('node:assert/strict'),crypto=require('node:crypto'),{JSDOM}=require('jsdom');
const html=fs.readFileSync('index.html','utf8'),meta=JSON.parse(fs.readFileSync('vendor/supabase-js-provenance.json','utf8')),path='vendor/supabase-js-'+meta.version+'.min.js',sdk=fs.readFileSync(path,'utf8');
assert.equal(crypto.createHash('sha256').update(sdk).digest('hex'),meta.sha256);assert(!html.includes('supabase-js@2'));
const dom=new JSDOM('<head></head>',{runScripts:'outside-only',url:'https://fixture.invalid'}),w=dom.window;
Object.assign(w,{fetch:null,Headers,Request,Response,TextEncoder,TextDecoder});w.CHEONGLA_CONFIG={supabaseUrl:'https://fixture.supabase.co',supabasePublishableKey:'sb_publishable_fixture'};
const payload=Buffer.from(JSON.stringify({sub:'10000000-0000-0000-0000-000000000001',exp:Math.floor(Date.now()/1000)+3600})).toString('base64url'),token='eyJhbGciOiJIUzI1NiJ9.'+payload+'.fixture',calls=[];let rejected=false,loaded=0;
w.fetch=async(url,init={})=>{calls.push(String(url));if(String(url).includes('/token'))return new Response(JSON.stringify(rejected?{msg:'Invalid login credentials',code:'invalid_credentials'}:{access_token:token,refresh_token:'fixture-refresh',expires_in:3600,token_type:'bearer',user:{id:'10000000-0000-0000-0000-000000000001',email:'fixture@example.invalid'}}),{status:rejected?400:200,headers:{'Content-Type':'application/json'}});if(String(url).includes('/logout'))return new Response(null,{status:204});throw Error('Unexpected network URL '+url);};
const append=w.document.head.appendChild.bind(w.document.head);w.document.head.appendChild=node=>{assert(node.getAttribute('src').startsWith(path));loaded++;w.eval(sdk);queueMicrotask(()=>node.onload());return append(node);};
w.eval('let clientPromise=null;'+html.slice(html.indexOf('async function getClient(){'),html.indexOf('function clearAccount(){')));
(async()=>{let client;
 try{const [a,b]=await Promise.all([w.getClient(),w.getClient()]);client=a;assert.equal(a,b);assert.equal(loaded,1);
 const result=await a.auth.signInWithPassword({email:'fixture@example.invalid',password:'fixture-only'});assert.equal(result.error,null);assert.equal(result.data.user.id,'10000000-0000-0000-0000-000000000001');assert.equal((await a.auth.getSession()).data.session.access_token,token);assert(w.localStorage.length>0);
 const signout=await a.auth.signOut();assert.equal(signout.error,null);assert.equal((await a.auth.getSession()).data.session,null);rejected=true;const failure=await a.auth.signInWithPassword({email:'fixture@example.invalid',password:'wrong-fixture'});assert(failure.error);assert.equal((await a.auth.getSession()).data.session,null);assert(calls.every(url=>url.startsWith('https://fixture.supabase.co/')));
 console.log('PASS pinned local SDK checksum, actual app loader/concurrent reuse, simulated auth success/session persistence/logout/invalid-credentials. No production login or CDN used.');
 }finally{client?.auth.stopAutoRefresh();dom.window.close();}
})().catch(e=>{console.error(e);process.exit(1)});
