const dialog = document.getElementById('homeTourDialog');
const video = document.getElementById('homeTourVideo');
const open = document.getElementById('homeTourOpen');
const close = document.getElementById('homeTourClose');
const status = document.getElementById('homeTourStatus');
let attempt = 0;
open.addEventListener('click', async () => {
  const current = ++attempt;
  if (!video.hasAttribute('src')) video.src = 'https://cheongla-winter-2027.logincj.chatgpt.site/videos/cheongla-tour.mp4';
  if (!dialog.open) dialog.showModal();
  try {
    await video.play();
    if (current !== attempt || !dialog.open) video.pause();
    else status.textContent = '음량 버튼으로 소리를 켜거나 전체화면으로 볼 수 있습니다.';
  } catch {
    if (dialog.open) status.textContent = '영상의 재생 버튼을 눌러 주세요. 연결이 원활하지 않으면 아래 별도 화면을 이용해 주세요.';
  }
});
close.addEventListener('click', () => dialog.close());
dialog.addEventListener('click', event => {
  if (event.target !== dialog) return;
  const rect = dialog.getBoundingClientRect();
  if (event.clientX < rect.left || event.clientX > rect.right || event.clientY < rect.top || event.clientY > rect.bottom) dialog.close();
});
dialog.addEventListener('close', () => { attempt++; video.pause(); open.focus({preventScroll:true}); });
video.addEventListener('error', () => { status.textContent = '영상을 불러오지 못했습니다. 인터넷 연결을 확인하거나 아래 별도 화면을 이용해 주세요.'; });
document.addEventListener('visibilitychange', () => { if (document.hidden) { attempt++; video.pause(); } });
window.addEventListener('pagehide', () => { attempt++; video.pause(); });
