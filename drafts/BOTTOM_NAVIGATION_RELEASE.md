# Bottom navigation — v2.0.13

The former module positioned the navigation absolutely at visualViewport.pageTop
plus visualViewport.height. Keyboard resize/pan values can remain stale after
focusout on mobile WebKit, leaving that document-positioned bar over journal text.
The previous workaround also needed JavaScript updates during scrolling.

The bar now remains a direct body child with CSS fixed/bottom:0 positioning.
Document top/left/width/transform overrides and the absolute-position selector
are removed. VisualViewport is used only to hide navigation while editing, during
keyboard/pan recovery and while pinch zooming. Color-toolbar focus is included.
The same reserved space, width cap, safe-area padding and history-owned `hidden`
state are retained. Focusout settling checks retry asynchronously; scrolling no
longer sets document coordinates.

The DOM regression fixture seeds stale absolute geometry and viewport scroll/pan
metrics, reproduces focus -> smaller keyboard viewport -> blur before viewport
restoration, then restores height and offset independently. It also covers toolbar
focus, contenteditable, zoom, rotation, desktop input and unchanged history state.
Existing swipe, detail/workspace navigation and score navigation checks pass.
These metrics are simulated; physical iOS keyboard/compositor behavior still
needs confirmation on a device. No journal data or editing functions are changed.
