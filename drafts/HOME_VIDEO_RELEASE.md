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
