import { Capacitor } from '@capacitor/core';
import { App } from '@capacitor/app';
import { Browser } from '@capacitor/browser';
import { Camera, MediaTypeSelection } from '@capacitor/camera';
import { createClient } from '@supabase/supabase-js';

// Bundle the login library locally so startup does not rely on a CDN script.
window.supabase={createClient};
const active=Capacitor.isNativePlatform();
window.CheonglaNative={active,renderPushPending(){
  const panel=document.getElementById('pushSettings');
  if(!panel)return;
  panel.hidden=false;
  for(const id of ['pushEnable','pushDisable','pushTest','pushServerSetup']){
    const button=document.getElementById(id);if(button){button.hidden=true;button.disabled=true;}
  }
  document.getElementById('pushStatus').textContent='휴대전화 알림을 준비 중입니다. 새 알림은 알림함에서 확인해 주세요.';
}};

export async function photosToInput(input,photos){
  if(!input.isConnected||input.disabled)return;
  const transfer=new DataTransfer();
  for(const photo of photos.slice(0,3)){
    const response=await fetch(photo.webPath);
    if(!response.ok)throw new Error('사진을 불러오지 못했습니다.');
    const blob=await response.blob();
    transfer.items.add(new File([blob],`question-${Date.now()}-${transfer.items.length}.${photo.metadata?.format||'jpeg'}`,{type:blob.type||'image/jpeg'}));
  }
  if(!input.isConnected||input.disabled)return;
  input.files=transfer.files;input.dispatchEvent(new Event('change',{bubbles:true}));
}

function addPhotoActions(input){
  if(input.dataset.nativePhotos||!input.accept.startsWith('image/'))return;
  input.dataset.nativePhotos='true';
  const controls=document.createElement('div');controls.className='native-photo-actions';
  const gallery=document.createElement('button');gallery.type='button';gallery.textContent='사진 선택';
  const take=document.createElement('button');take.type='button';take.textContent='사진 촬영';
  const status=document.createElement('span');status.setAttribute('role','status');
  controls.append(gallery,take,status);input.after(controls);
  async function choose(source){
    if(input.disabled)return;gallery.disabled=take.disabled=true;status.textContent='';
    try{
      const photos=source==='gallery'?(await Camera.chooseFromGallery({mediaType:MediaTypeSelection.Photo,allowMultipleSelection:true,limit:3,quality:85,includeMetadata:true})).results:
        [await Camera.takePhoto({quality:85,includeMetadata:true})];
      await photosToInput(input,photos);
    }catch(error){
      // Cancellation has no effect on the existing selection.
      if(!/cancel/i.test(error?.message||''))status.textContent='사진을 선택하지 못했습니다. 아래 파일 선택으로 다시 시도해 주세요.';
    }finally{gallery.disabled=take.disabled=false;}
  }
  gallery.addEventListener('click',()=>void choose('gallery'));
  take.addEventListener('click',()=>void choose('camera'));
}

async function startNativeShell(){
  if(!active)return;
  await App.addListener('backButton',()=>{
    if((history.state?.cheonglaView?.index||0)>0)history.back();else void App.minimizeApp();
  });
  await App.addListener('appRestoredResult',event=>{
    if(event.pluginId==='Camera')alert('앱이 다시 열렸습니다. 첨부할 사진을 다시 선택해 주세요.');
  });
  document.addEventListener('click',event=>{
    const link=event.target.closest?.('a[href]');if(!link||event.defaultPrevented)return;
    let url;try{url=new URL(link.href,location.href);}catch{return;}
    if(url.protocol==='https:'&&url.origin!==location.origin){
      event.preventDefault();void Browser.open({url:url.href}).catch(()=>{alert('연결하지 못했습니다. 잠시 후 다시 시도해 주세요.');});
    }
  });
  const offline=document.createElement('div');offline.className='native-offline';offline.setAttribute('role','status');
  offline.textContent='인터넷 연결을 확인해 주세요. 연결되면 다시 이용할 수 있습니다.';document.body.prepend(offline);
  const updateConnection=()=>{offline.hidden=navigator.onLine;};updateConnection();
  window.addEventListener('online',updateConnection);window.addEventListener('offline',updateConnection);
  const observePhotos=()=>document.querySelectorAll('input[type="file"]').forEach(addPhotoActions);
  observePhotos();new MutationObserver(observePhotos).observe(document.body,{childList:true,subtree:true});
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',()=>void startNativeShell(),{once:true});else void startNativeShell();
