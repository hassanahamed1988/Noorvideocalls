# v2.4 – Forward for every message + swipe to forward

- **Forward now works for every message type**: text, photo, video and voice (long press > Forward).
- **Swipe a message to the LEFT or to the RIGHT** (hold and drag) and the Forward sheet opens. Same look as the message action sheet: a **search box** (name or number) and your **groups and contacts** to tick, then Send. Pick one or many.
- Forwarded messages show a small "Forwarded" label.
- **Voice messages** still follow Settings > Privacy > Who Can Share My Voice Messages of the person who originally recorded them (Nobody / Everyone / picked contacts). If it is not allowed, the swipe shows "The sender does not allow this voice message to be forwarded". View-once voice messages and deleted messages never forward.
- Checked on the **server** too (`POST /messages/forward`, now for text / image / video / voice), so a modified app cannot bypass the voice rule.

Files: server/index.js, app/lib/main.dart, app/lib/contact_strings.dart, app/pubspec.yaml (2.4.0+15).
