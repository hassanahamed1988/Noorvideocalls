# Noor Video Calls v1.8 — changes

## Server (server/index.js)
- Presence: "online" now means a live socket whose app is in the FOREGROUND (app sends `app-state`). Background / killed / network-lost => offline + Last Seen immediately (dead links detected in ~10 s via 5 s ping).
- Delivery receipts: `delivered` is recorded only when the receiving phone confirms (socket `delivered` event, or when it downloads the chat / chat list). `seen` as before (respects read-receipt privacy). `GET /messages` returns `deliveredAt`, `seenAt`, `rcpt[]` (per person, for groups).
- Reply support: `reply` (text msg) / `X-Reply` header (media) -> stored and returned as `reply`.
- Calls: new `/call/ringing`, `/call/end`, `/call/state`; `/call/join` records answer time. `/calls` returns avatar, phones, answered, duration (ms, from answer to hang-up).
- Socket events: `call-ringing`, `call-answered`, `call-ended`.

## App
1. Add Contact (existing account) -> opens that user's chat.
2. Chat header: no profile photo, name up to 2 lines, bigger bar; online dot + status.
3. Lifecycle-aware presence (foreground/background), auto-reconnect resync.
4. Call screens: centered round photo, day/night gradient, pulse animation; "Calling…" -> "Ringing…" (only after receiver phone shows the call) -> timer starts only after answer. Minimize icon top-left keeps the call alive (green "tap to return" bar on every screen).
5. Video: own frame long-press hides / long-press again restores; remote video full screen, responsive layout.
6. "Calls History" page: photo, name, 12-hour time, duration, working audio/video call buttons.
7. All times 12-hour (6:00 PM).
8. Message long-press: Reply (with quote), Share (text/photo/video), Details (Sent / Delivered / Seen + exact time); info icon on every bubble.

## Needs before building
- `flutter pub get` (new dependency: share_plus ^10.1.4)
- Restart the server (`npm start`); existing old messages keep "Sent" only (no delivery data existed).
