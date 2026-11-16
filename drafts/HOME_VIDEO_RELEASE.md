# Home video previews and visibility — v2.0.11

Uploaded tour videos previously received only a text play button. Only the
original tour video used a poster. All tour videos now use a visual preview:
original poster, saved upload cover, or muted inline metadata/first-frame fallback.
The playback dialog remains the click target; preview elements never autoplay.

The supplied currently published upload was read through the public Storage
access path and decoded locally. It is a 1080×1920 HEVC MP4, 14.63 seconds long.
A JPEG from its first second was attached to that same video using its current
path and revision. The uploaded file, title and visibility flags were preserved.

Future uploads attempt JPEG cover extraction locally in the uploader's browser,
with bounded dimensions/size, a timeout and object-URL cleanup. A failed decode
does not block uploading; the editor explicitly reports the video-preview
fallback. No paid image/recognition service is involved.

Two nullable cover columns retain existing RLS and column-specific editor grants.
A binding trigger clears covers when a different video replaces/restores the file,
preventing mismatched thumbnails. Hiding or archiving the same content preserves
its cover. Video-file trash/cleanup behavior is unchanged.

Principals can hide visible videos directly on the home card or use the video
visibility list in Home Content Management to hide/show each video. Tour-video
hiding removes the entire home card, including legacy video_hidden records.
Restoring visibility clears both flags. Hiding never removes video files. No
existing video was automatically hidden during this release.

Validation: isolated PostgreSQL RLS/column grants/JPEG validation/cover binding;
DOM upload-cover save, hide/show, original/upload/legacy visibility, error fallback,
stale signing and viewer/logout controls; local decoder lifecycle tests; existing
home video playback/trash/cleanup and mobile swipe/MBTI permissions. Browser media
events are simulated in unit checks; the actual existing MP4 was independently
decoded to verify its real cover.

## v2.0.12 — swipe to reveal trash

Active principals can swipe a home video card or its management-list row left to
reveal a red trash-icon button on phones/tablets. Swiping does not archive the
record. Clicking the action opens the existing confirmation and then uses the
same revision-checked `archived_at` update; the normal trash screen can restore
it. Desktop users get an inline trash button. Hiding remains a separate action.

Only one local action tray opens at a time. Right swipe, outside tap and Escape
close it. Vertical scrolling, short touches, pinch/cancel and playback-click
suppression are covered. Owner card gestures take priority over the video rail;
its previous/next controls remain available. Other app-history swipes and viewer
video rails retain their behavior. Local swipe rows are excluded from the global
history gesture recognizer. Refresh, busy-save and logout paths dispose/rebind
row handlers and remove privileged actions.

Checks: `home-video-swipe.cjs` drives touch/keyboard/role and history interaction;
`home-video-preview.cjs` verifies confirmed/canceled trash, refresh reattachment,
poster/file preservation and viewer cleanup. Existing home content, swipe,
principal-only MBTI and score navigation checks pass. Gesture events are simulated;
physical iPhone/iPad gesture feel has not been measured.


## v2.0.14 — direct editing and video captions
- Principal-only 수정 buttons on each published video and visibility-management row open the existing editor with that exact record selected. Existing revision-checked save and role policies are unchanged.
- Video description follows the preview and preserves line breaks on all screen sizes. Editor label explains placement.
- Local JPEG generation checks sampled pixel luminance and skips black opening frames, retaining the earliest visible sampled scene. No new service or paid API.
- Current winter-school video had a 3,855-character blank poster; replaced only its poster using the first readable scene at one second, with an id/path/revision guard. Revision 2 → 3. Title, description, video, visibility unchanged.
- Passed DOM integration: correct-record edit, title/description save, caption order, original video preservation, logout permissions; simulated decoder tests include dark-opening recovery. Existing swipe, playback and bottom navigation checks passed. Physical iPhone/iPad decoding has not been exercised.
