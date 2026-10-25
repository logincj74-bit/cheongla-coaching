/* Phone identifiers use a reserved, non-deliverable Auth alias. This is an ID,
   not proof of phone ownership; staff approval and parent linking stay mandatory.
   No SMS provider, service key, or elevated permission is used by this client. */
(function(root){
 const suffix='@phone.cheongla.invalid';
 function phone(value){const n=String(value||'').replace(/[^0-9]/g,'');if(!/^01[016789][0-9]{7,8}$/.test(n))throw Error('올바른 휴대전화번호를 입력해 주세요.');return n;}
 function isPhoneIdentity(email){return /^[a-f0-9]{64}@phone\.cheongla\.invalid$/i.test(email||'');}
 async function identifier(method,value){if(method==='phone'){const n=phone(value),bytes=await root.crypto.subtle.digest('SHA-256',new TextEncoder().encode(n));return Array.from(new Uint8Array(bytes),x=>x.toString(16).padStart(2,'0')).join('')+suffix;}if(method!=='email')throw Error('이메일 또는 휴대전화번호 방식을 선택해 주세요.');const e=String(value||'').trim().toLowerCase();if(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(e)||e.endsWith(suffix))throw Error('올바른 이메일을 입력해 주세요.');return e;}
 function displayIdentity(email,registeredPhone){return isPhoneIdentity(email)?(registeredPhone||'휴대전화번호로 가입'):email||'미등록';}
 function installVisibility(doc){for(const id of ['password','passwordConfirm','forcedPassword','forcedPasswordConfirm']){const input=doc.getElementById(id);if(!input||doc.getElementById(id+'Visibility'))continue;const row=doc.createElement('div');row.className='password-input-row';input.before(row);row.append(input);const button=doc.createElement('button');button.id=id+'Visibility';button.type='button';button.className='secondary password-visibility';button.textContent='보기';button.setAttribute('aria-controls',id);button.setAttribute('aria-label',(id.includes('Confirm')?'확인 비밀번호':'비밀번호')+' 보기');button.setAttribute('aria-pressed','false');button.addEventListener('click',()=>{const show=input.type==='password';input.type=show?'text':'password';button.textContent=show?'숨기기':'보기';button.setAttribute('aria-pressed',String(show));button.setAttribute('aria-label',show?'비밀번호 숨기기':'비밀번호 보기');});row.append(button);}}
 function mask(doc){for(const id of ['password','passwordConfirm','forcedPassword','forcedPasswordConfirm']){const x=doc.getElementById(id),b=doc.getElementById(id+'Visibility');if(x)x.type='password';if(b){b.textContent='보기';b.setAttribute('aria-pressed','false');b.setAttribute('aria-label','비밀번호 보기');}}}
 root.CheonglaAuth=Object.freeze({phone,isPhoneIdentity,identifier,displayIdentity,installVisibility,mask});
})(globalThis);
