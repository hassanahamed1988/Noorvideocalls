# Sticker packs

Every folder in `server/stickers/` is one sticker pack. Put the sticker pictures inside it:

```
server/stickers/
  my_pack/
    pack.json      (optional)
    hello.png
    thanks.webp
    dance.gif
```

* Pictures: PNG, WebP or GIF (animated WebP / GIF work too). Transparent background looks best, 512 x 512 px or smaller, under ~300 KB each.
* File and folder names: letters, digits, `_`, `-`, `.` only (no spaces).
* `pack.json` (optional) - the pack name and its tab icon:

```json
{
  "name": { "en": "My pack", "bn": "আমার প্যাক", "ar": "حزمتي", "hi": "मेरा पैक" },
  "icon": "hello.png",
  "order": 10
}
```
  `name` can also be a plain string. `order` decides the tab position (smaller = first). Without `pack.json` the folder name is the title and the first picture is the icon.
* No server restart: the app asks the server for the list each time the sticker panel opens (cached for 1 minute). Delete a folder and the pack disappears.
* `sample_smileys` is only an example - delete it when you add your own packs.
* The built-in pack "Emoji stickers" is inside the app and needs no files.
