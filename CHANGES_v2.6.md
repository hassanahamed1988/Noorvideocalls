# v2.6 – Premium chat composer, emoji picker, stickers

## Composer (message box)
- New rounded **pill** message box: emoji button, multi-line text (grows up to 5 lines), attach button and a quick **camera** button (hides while typing / on very narrow screens). The border glows when focused.
- One round button that **morphs** (rotate + scale) between **microphone** and **send**; press-scale feedback and haptics on every button.
- The phone keyboard's own emoji / GIF keys keep working in the text box. Enter now inserts a new line; use the send button.
- **Attach sheet** redesigned: round gradient tiles (Camera, Gallery, Video, Record video, Document) that pop in one after another; adapts to 3 or 4 columns by screen width.
- **Voice recording panel**: waveform inside a soft pill, pressable round buttons with glow, hold-to-record mic grows and turns red.

## Emoji + stickers (the app's own picker)
- Tap the emoji button: the **keyboard turns into the panel** (same height, animated); tap the text box or the keyboard icon to come back; the Back button closes the panel.
- **Emoji tab**: Recent + 9 categories (smileys, people, animals & nature, food, activities, travel, objects, symbols, flags). Tap = insert at the cursor. Backspace button deletes a whole emoji (hold to repeat).
- **Stickers tab**: built-in **Emoji stickers** + every sticker pack found on the server. Tap a sticker = sent at once. Stickers show big, without a bubble, and a new one pops in. They are cached on the phone after the first download.
- Stickers can be replied to, forwarded and deleted like other messages; chat list shows "🖼 Sticker".

## Server
- `GET /stickers` – list of packs (folders in `server/stickers/`). **No restart** needed to add a pack; see `server/stickers/README.md`.
- `POST /messages/sticker` {chat, pack, file, reply?} – checks the pack/file really exists (or, for the built-in pack, that it is an emoji), then behaves like a normal message (blocked / disabled / timers / notifications).
- `/stickers/...` serves images only (png / webp / gif). `POST /messages/forward` also forwards stickers.
- `server/stickers/sample_smileys` is only a sample: delete it when you add your own packs.

## Adding your own sticker pack
1. Make a folder `server/stickers/my_pack/`.
2. Put PNG / WebP / GIF files inside (transparent background, up to 512 x 512).
3. Optional `pack.json` for the name (en / bn / ar / hi) and the tab icon.
4. Open the sticker panel in the app: the pack is there.

Files: server/index.js, app/lib/main.dart, app/lib/composer_kit.dart (new), app/lib/contact_strings.dart, app/lib/contact_info.dart, app/pubspec.yaml (2.6.0+17), server/stickers/*.
Needs: restart the server (once, for the new endpoints) and rebuild the app. No new packages.
