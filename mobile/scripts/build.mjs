import { build } from 'esbuild';
import { readFile, writeFile, cp, mkdir, rm } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const source=resolve(root,'..');
const out=resolve(root,'www');
await rm(out,{recursive:true,force:true});
await mkdir(out,{recursive:true});
let html=await readFile(resolve(source,'index.html'),'utf8');
const marker='<script src="config.js"></script>';
if(!html.includes(marker))throw new Error('원본 앱의 연결 설정 위치를 확인해 주세요.');
html=html.replace(marker,'<script src="native-runtime.js"></script>\n'+marker);
// Browser Web Push subscriptions cannot deliver to APNs/FCM native devices.
const pushMarker='async function loadPushSettings(){';
if(!html.includes(pushMarker))throw new Error('알림 설정 코드가 변경됐습니다. 네이티브 연결을 검토해 주세요.');
html=html.replace(pushMarker,pushMarker+"if(window.CheonglaNative?.active){window.CheonglaNative.renderPushPending();return;}");
html=html.replace('</head>',`<style>body{padding-top:env(safe-area-inset-top);padding-bottom:env(safe-area-inset-bottom)}.native-offline{position:sticky;top:0;z-index:100;background:#183d47;color:white;padding:12px;text-align:center}.native-photo-actions{display:flex;gap:8px;margin:10px 0}</style></head>`);
await writeFile(resolve(out,'index.html'),html);
await cp(resolve(source,'assets'),resolve(out,'assets'),{recursive:true});
await cp(resolve(source,'config.js'),resolve(out,'config.js'));
await cp(resolve(source,'manifest.webmanifest'),resolve(out,'manifest.webmanifest'));
await build({entryPoints:[resolve(root,'src/native-shell.js')],outfile:resolve(out,'native-runtime.js'),bundle:true,format:'iife',platform:'browser',target:['es2022'],minify:true});
console.log('청라 설치형 앱 화면 묶음 생성 완료. 서명된 설치 파일은 아직 생성하지 않았습니다.');
