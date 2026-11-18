from pathlib import Path
import json,base64,sys
root=Path(__file__).resolve().parent.parent
out=Path(sys.argv[1]);logo='data:image/png;base64,'+base64.b64encode((root/'assets/cheongla-icon-180-v2.png').read_bytes()).decode()
data=json.loads(Path(sys.argv[2]).read_text()) # Explicit private source path.
html='''<!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>청라 MBTI 개편 검토본</title><style>
body{margin:0;background:#f6f5ef;color:#233d42;font:16px/1.7 -apple-system,BlinkMacSystemFont,'Apple SD Gothic Neo','Malgun Gothic',sans-serif}main{max-width:1180px;margin:auto;padding:28px 24px 80px}.demo-brand{display:flex;align-items:center;gap:14px;font-weight:700}.demo-brand img{width:52px;height:52px}.demo-notice{padding:18px 20px;border:1px solid #dfcda2;border-radius:14px;background:#fff9e9;margin:24px 0}.demo-nav{display:flex;flex-wrap:wrap;gap:8px;padding-bottom:20px;border-bottom:1px solid #dce5df}.demo-nav button,.demo-tools button{border:1px solid #d2dfd5;background:white;border-radius:10px;padding:12px;font:inherit;color:#46695c;cursor:pointer}.demo-nav button.active{background:#205b50;color:white}.demo-nav button:disabled{cursor:default;opacity:.6}.demo-tools{display:flex;flex-wrap:wrap;gap:8px;margin-bottom:18px}.demo-tools strong{margin-right:auto}.demo-modal{border:1px solid #a7c2af;border-radius:18px;max-width:420px;width:calc(100vw - 56px);padding:24px;color:#233d42;background:#fff}.demo-modal::backdrop{background:#183d4766}.demo-modal button{font:inherit;padding:12px 20px;border:1px solid #b7cbc0;border-radius:10px;background:#edf4eb;cursor:pointer;margin-right:8px}@media(max-width:600px){main{padding:18px 14px 60px}.demo-brand{font-size:14px}.demo-nav button{flex:1;min-width:42%}.demo-notice{font-size:14px}}
</style></head><body><main><header class="demo-brand"><img alt="청라 로고" src="LOGO"><div>전주 독학재수 청라학원<br><small>MBTI 학습법 개편 검토본 · 2026. 11. 16.</small></div></header>
<div class="demo-notice"><strong>배포 전 검토 화면입니다.</strong><br>20개 수정본과 12개 항목을 모두 담았습니다. 수정·저장·삭제·휴지통 기능은 이 화면에서만 임시 체험되며, 새로고침하면 원래 자료로 돌아갑니다. 운영 앱·서버에는 반영하지 않았습니다.</div>
<nav class="demo-nav" aria-label="MBTI 하위 메뉴"><button disabled>MBTI 학습법 소개 · 유지</button><button disabled>MBTI 여섯 그룹 학습 성향 · 유지</button><button disabled>학부모 MBTI 학습지도 안내 · 추후 수정</button><button class="active">기질·유형별 MBTI 학습법</button></nav>
<div class="demo-tools"><strong>변경 대상: 마지막 하위 메뉴</strong><button id="demoMode">열람 보기로 전환</button><button id="demoReset">체험 내용 초기화</button></div><section id="mbtiLibraryRoot"></section></main>
<dialog id="demoConfirm" class="demo-modal"><h3>확인해 주세요</h3><p></p><button id="demoConfirmYes">확인</button><button id="demoConfirmNo">취소</button></dialog>'''.replace('LOGO',logo)
for path in ['print-tools.js','print-pdf.js','mbti-library.js','drafts/mbti-preview-adapter.js']:
 html+='<script>'+ (root/path).read_text().replace('</script','<\\/script')+'</script>'
payload=json.dumps(data,ensure_ascii=False).replace('<','\\u003c')
html+='<script>const reviewData='+payload+';const reviewLogo='+json.dumps(logo)+';'+'''
let reviewLogoPromise;window.CheonglaDocumentBrand={name:'전주 독학재수 청라학원',logoUrl:reviewLogo,loadLogo:()=>reviewLogoPromise||(reviewLogoPromise=new Promise((resolve,reject)=>{const image=new Image();image.onload=()=>resolve(image);image.onerror=reject;image.src=reviewLogo;}))};
const profile={id:'review-principal',role:'owner'},fixture=CheonglaMBTIPreview.make(reviewData);let manage=true;
function confirmReview(text){return new Promise(resolve=>{const dialog=document.getElementById('demoConfirm');dialog.querySelector('p').textContent=text;function done(value){dialog.close();resolve(value);}document.getElementById('demoConfirmYes').onclick=()=>done(true);document.getElementById('demoConfirmNo').onclick=()=>done(false);dialog.oncancel=event=>{event.preventDefault();done(false);};dialog.showModal();});}
const reviewUI=CheonglaMBTILibrary.mount({document,profile:()=>profile,canUse:()=>true,canEdit:()=>manage,confirm:confirmReview,readable:error=>error.message,rpc:fixture.rpc,preference:fixture.preference,savePreference:fixture.savePreference,operations:()=>confirmReview('학생별 학습 처방은 기존 앱과 연결할 예정입니다. 이 검토 파일에서는 실제 학생 정보에 연결하지 않습니다.')});
document.getElementById('demoMode').onclick=async()=>{if(!await reviewUI.leave())return;manage=!manage;reviewUI.reset();await reviewUI.open();document.getElementById('demoMode').textContent=manage?'열람 보기로 전환':'관리 보기로 전환';};
document.getElementById('demoReset').onclick=async()=>{if(!await confirmReview('체험 중 변경한 내용을 지우고 처음 자료로 돌아갈까요?'))return;fixture.reset();reviewUI.reset();await reviewUI.open();};
void reviewUI.open();
</script></body></html>'''
out.parent.mkdir(parents=True,exist_ok=True);out.write_text(html);print(out, out.stat().st_size)
