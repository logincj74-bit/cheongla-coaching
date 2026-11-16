/* Create a small cover locally from the selected file; no recognition or paid API. */
(function(root){'use strict';
function create(file){
 if(!file||!root.URL?.createObjectURL)return Promise.resolve(null);
 return new Promise(resolve=>{
  const doc=root.document,video=doc.createElement('video');let url,timer,done=false,target=0,frames=[],frame=0,best=null,bestScore=-1;
  function finish(poster){if(done)return;done=true;root.clearTimeout(timer);
   video.onloadedmetadata=video.onloadeddata=video.onseeked=video.onerror=null;
   try{video.pause();video.removeAttribute('src');video.load();}catch(_){}
   if(url)root.URL.revokeObjectURL(url);resolve(poster);
  }
  function capture(){if(done||video.seeking||video.readyState<2||!video.videoWidth||!video.videoHeight)return;
   try{const canvas=doc.createElement('canvas'),scale=Math.min(1,480/video.videoWidth,854/video.videoHeight);
    canvas.width=Math.max(1,Math.round(video.videoWidth*scale));canvas.height=Math.max(1,Math.round(video.videoHeight*scale));
    const ctx=canvas.getContext('2d');if(!ctx){finish(null);return;}ctx.drawImage(video,0,0,canvas.width,canvas.height);
    const pixels=ctx.getImageData(0,0,canvas.width,canvas.height).data;
    let light=0,total=0;
    for(let i=0;i<pixels.length;i+=64){const y=.2126*pixels[i]+.7152*pixels[i+1]+.0722*pixels[i+2];if(y>30)light++;total++;}
    const score=light/Math.max(1,total);
    let poster=null;
    for(const quality of [.75,.6,.45]){const candidate=canvas.toDataURL('image/jpeg',quality);if(candidate.startsWith('data:image/jpeg;base64,')&&candidate.length<=160000){poster=candidate;break;}}
    if(poster&&score>bestScore){best=poster;bestScore=score;}
    // Skip a black opening/fade; keep the earliest visible scene instead of a blank cover.
    if(poster&&score>=.06){finish(poster);return;}
    if(++frame<frames.length){target=frames[frame];video.currentTime=target;return;}
    finish(bestScore>=.03?best:null);
   }catch(_){finish(null);}
  }
  video.muted=true;video.defaultMuted=true;video.playsInline=true;video.setAttribute('muted','');video.setAttribute('playsinline','');video.preload='auto';
  video.onloadedmetadata=()=>{const end=Number.isFinite(video.duration)&&video.duration>0?Math.max(0,video.duration-.05):0;frames=[...new Set([1,2,3,5,8,12].map(t=>Math.min(t,end)))];target=frames[0];try{if(target>0)video.currentTime=target;else capture();}catch(_){capture();}};
  video.onloadeddata=()=>{if(Math.abs(video.currentTime-target)<.2)capture();};video.onseeked=capture;video.onerror=()=>finish(null);
  timer=root.setTimeout(()=>finish(null),10000);
  try{url=root.URL.createObjectURL(file);video.src=url;video.load();}catch(_){finish(null);}
 });
}
root.CheonglaVideoPoster={create};
})(globalThis);
