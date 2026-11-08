const dialog = document.getElementById('homeTourDialog');
const video = document.getElementById('homeTourVideo');
const open = document.getElementById('homeTourOpen');
const close = document.getElementById('homeTourClose');
const status = document.getElementById('homeTourStatus');
let attempt = 0;
const countdown = document.getElementById('homeCountdownVideo');
const external = document.getElementById('homeTourExternal');
const heading = document.getElementById('homeTourDialogTitle');
const poster = video.poster;
let opener = open;

async function play(event) {
  opener = event.currentTarget;
  const kind = opener.dataset.homeFeatureVideo;
  const current = ++attempt;
  video.pause();
  video.removeAttribute('src');
  video.load();
  video.poster = kind === 'tour' ? poster : '';
  external.hidden = true;
  status.textContent = '영상을 불러오는 중입니다…';
  heading.textContent = kind === 'tour' ? '청라 내부 영상 둘러보기' : '수능 응원 영상';
  if (!dialog.open) dialog.showModal();
  try {
    const source = await globalThis.CheonglaHomeFeaturesUI.video(kind);
    if (current !== attempt || !dialog.open) return;
    if (!source) throw new Error('동영상이 없습니다.');
    heading.textContent = source.title;
    video.setAttribute('aria-label', source.title);
    external.href = source.url;
    external.hidden = false;
    video.src = source.url;
    await video.play();
    if (current === attempt && dialog.open) status.textContent = '음량 버튼으로 소리를 켜거나 전체화면으로 볼 수 있습니다.';
  } catch {
    if (current === attempt && dialog.open) status.textContent = external.hidden
      ? '영상을 불러오지 못했습니다. 잠시 후 다시 열어 주세요.'
      : '영상의 재생 버튼을 눌러 주세요. 연결이 원활하지 않으면 아래 별도 화면을 이용해 주세요.';
  }
}
open.addEventListener('click', play);
countdown.addEventListener('click', play);
close.addEventListener('click', () => dialog.close());
dialog.addEventListener('click', event => {
  if (event.target !== dialog) return;
  const rect = dialog.getBoundingClientRect();
  if (event.clientX < rect.left || event.clientX > rect.right || event.clientY < rect.top || event.clientY > rect.bottom) dialog.close();
});
dialog.addEventListener('close', () => { attempt++; video.pause(); opener.focus({preventScroll:true}); });
video.addEventListener('error', () => { if (!video.hasAttribute('src')) return; status.textContent = '영상을 불러오지 못했습니다. 인터넷 연결을 확인하거나 아래 별도 화면을 이용해 주세요.'; });
document.addEventListener('visibilitychange', () => { if (document.hidden) { attempt++; video.pause(); } });
window.addEventListener('pagehide', () => { attempt++; video.pause(); });
