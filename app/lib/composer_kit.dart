// Premium chat composer kit.
//
//   * PressScale        – any widget that gently shrinks while pressed (buttons, emoji cells, tiles)
//   * attachGrid        – the animated "send photo / video / document" tiles
//   * EmojiStickerPanel – the app's own emoji picker + sticker picker (the phone keyboard's emoji still work in the text box)
//   * StickerView / StickerImg – how a sticker message is drawn (big, no bubble, cached on the phone)
//
// Sticker packs live on the SERVER: server/stickers/<pack>/*.png|webp|gif (+ optional pack.json). The app asks GET /stickers,
// so a new pack appears in every phone without an app update. The pack "emoji" is built in (big emoji, no files).
import 'dart:async';
import 'dart:io' show Directory, File;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'main.dart';

/// Gently shrinks its child while it is pressed.
class PressScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  const PressScale({super.key, required this.child, this.onTap, this.scale = .9});
  @override
  State<PressScale> createState() => _PS();
}

class _PS extends State<PressScale> {
  bool down = false;
  @override
  Widget build(BuildContext c) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null ? null : (_) => setState(() => down = true),
      onTapUp: (_) => setState(() => down = false),
      onTapCancel: () => setState(() => down = false),
      onTap: widget.onTap,
      child: AnimatedScale(scale: down ? widget.scale : 1, duration: const Duration(milliseconds: 110), curve: Curves.easeOut, child: widget.child));
}

/// Attach sheet tiles: items = [[icon, label, value, color], ...]. Tiles pop in one after the other.
Widget attachGrid(BuildContext ctx, List<List<dynamic>> items) {
  final w = MediaQuery.of(ctx).size.width;
  final tile = ((w - 32) / (w < 380 ? 3 : 4)).clamp(78.0, 110.0).toDouble();
  Widget one(int i) {
    final color = items[i].length > 3 ? items[i][3] as Color : Theme.of(ctx).colorScheme.primary;
    return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: Duration(milliseconds: 260 + i * 70),
        curve: Curves.easeOutBack,
        builder: (_, v, ch) => Opacity(opacity: v.clamp(0.0, 1.0).toDouble(), child: Transform.scale(scale: .6 + .4 * v, child: ch)),
        child: SizedBox(
            width: tile,
            child: PressScale(
                onTap: () => Navigator.pop(ctx, items[i][2]),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                      width: 62,
                      height: 62,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [color, Color.lerp(color, Colors.black, .22) ?? color]),
                          boxShadow: [BoxShadow(color: color.withOpacity(.38), blurRadius: 12, offset: const Offset(0, 5))]),
                      child: Icon(items[i][0] as IconData, color: Colors.white, size: 29)),
                  const SizedBox(height: 8),
                  Text('${items[i][1]}', textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                ]))));
  }

  return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 14),
      child: Wrap(alignment: WrapAlignment.center, runSpacing: 14, children: [for (var i = 0; i < items.length; i++) one(i)]));
}

// ---- text helpers (insert an emoji at the cursor / delete one whole emoji) --------------------------------------

String dropLastCluster(String s) {
  if (s.isEmpty) return s;
  final r = s.runes.toList();
  bool joiner(int x) => x == 0x200D || x == 0xFE0F || (x >= 0x1F3FB && x <= 0x1F3FF) || (x >= 0xE0020 && x <= 0xE007F);
  var i = r.length - 1;
  while (true) {
    while (i > 0 && joiner(r[i])) {
      i--;
    }
    if (i > 0 && r[i - 1] == 0x200D) {
      i -= 2;
      if (i < 0) {
        i = 0;
        break;
      }
      continue;
    }
    if (r[i] >= 0x1F1E6 && r[i] <= 0x1F1FF && i > 0 && r[i - 1] >= 0x1F1E6 && r[i - 1] <= 0x1F1FF) i--;
    break;
  }
  return String.fromCharCodes(r.sublist(0, i));
}

TextEditingValue emojiInsert(TextEditingValue v, String s) {
  final sel = v.selection;
  final a = sel.isValid ? sel.start.clamp(0, v.text.length).toInt() : v.text.length;
  final b = sel.isValid ? sel.end.clamp(0, v.text.length).toInt() : v.text.length;
  return TextEditingValue(text: v.text.replaceRange(a, b, s), selection: TextSelection.collapsed(offset: a + s.length));
}

TextEditingValue emojiBackspace(TextEditingValue v) {
  final sel = v.selection;
  final a = sel.isValid ? sel.start.clamp(0, v.text.length).toInt() : v.text.length;
  final b = sel.isValid ? sel.end.clamp(0, v.text.length).toInt() : v.text.length;
  if (a != b) return TextEditingValue(text: v.text.replaceRange(a, b, ''), selection: TextSelection.collapsed(offset: a));
  if (a == 0) return v;
  final before = dropLastCluster(v.text.substring(0, a));
  return TextEditingValue(text: before + v.text.substring(a), selection: TextSelection.collapsed(offset: before.length));
}

// ---- sticker data + cache ---------------------------------------------------------------------------------------

List kStickerPacks = [];
int _kStickerAt = 0;

Future<void> refreshStickerPacks() async {
  final n = DateTime.now().millisecondsSinceEpoch;
  if (kStickerPacks.isNotEmpty && n - _kStickerAt < 60000) return;
  try {
    final r = await getj('/stickers');
    if (r is List) {
      kStickerPacks = r;
      _kStickerAt = n;
    }
  } catch (_) {}
}

String packTitle(Map p) {
  final n = p['name'];
  if (n is Map) return '${n[lang.value] ?? n['en'] ?? (n.values.isEmpty ? p['id'] : n.values.first)}';
  return '${n ?? p['id']}';
}

String stickerUrl(String pack, String file) => '$base/stickers/$pack/${Uri.encodeComponent(file)}';

final Map<String, Future<File?>> _stkFiles = {};
int _fnv(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0xFFFFFFFF;
  }
  return h;
}

/// Downloads a sticker once and keeps it on the phone, so it never downloads again.
Future<File?> stickerFile(String url) {
  final f = _stkFiles.putIfAbsent(url, () async {
    try {
      final ext = url.contains('.') ? url.split('.').last.toLowerCase() : 'png';
      final fl = File('${Directory.systemTemp.path}/stk_${_fnv(url).toRadixString(16)}.${ext.length > 5 ? 'png' : ext}');
      if (await fl.exists() && await fl.length() > 0) return fl;
      final r = await http.get(Uri.parse(url));
      if (r.statusCode != 200 || r.bodyBytes.isEmpty) return null;
      await fl.writeAsBytes(r.bodyBytes);
      return fl;
    } catch (_) {
      return null;
    }
  });
  f.then((v) {
    if (v == null) _stkFiles.remove(url);
  });
  return f;
}

class StickerImg extends StatelessWidget {
  final String url;
  final double size;
  const StickerImg(this.url, {super.key, this.size = 100});
  @override
  Widget build(BuildContext c) => SizedBox(
      width: size,
      height: size,
      child: FutureBuilder<File?>(
          future: stickerFile(url),
          builder: (_, s) {
            final f = s.data;
            if (f != null) return Image.file(f, fit: BoxFit.contain, gaplessPlayback: true, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined));
            if (s.connectionState == ConnectionState.done) return const Icon(Icons.broken_image_outlined);
            return const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)));
          }));
}

/// A sticker message: big, no bubble. A brand-new one pops in.
class StickerView extends StatelessWidget {
  final Map m;
  const StickerView(this.m, {super.key});
  @override
  Widget build(BuildContext c) {
    final pack = '${m['pack']}', file = '${m['file']}';
    final fresh = m['ts'] is num && DateTime.now().millisecondsSinceEpoch - (m['ts'] as num) < 4000;
    final Widget core = pack == 'emoji'
        ? SizedBox(height: 112, child: Center(child: Text(file, style: const TextStyle(fontSize: 82, height: 1.1))))
        : StickerImg(stickerUrl(pack, file), size: 140);
    if (!fresh) return core;
    return TweenAnimationBuilder<double>(
        tween: Tween(begin: .4, end: 1.0), duration: const Duration(milliseconds: 460), curve: Curves.elasticOut, builder: (_, v, ch) => Transform.scale(scale: v, child: ch), child: core);
  }
}

// ---- emoji data ---------------------------------------------------------------------------------------------------

List<String> _e(String s) => s.split(' ').where((x) => x.isNotEmpty).toList();

final List<List<String>> kEmojiCats = [
  _e('😀 😃 😄 😁 😆 😅 🤣 😂 🙂 🙃 😉 😊 😇 🥰 😍 🤩 😘 😗 ☺️ 😚 😙 🥲 😋 😛 😜 🤪 😝 🤑 🤗 🤭 🤫 🤔 🤐 🤨 😐 😑 😶 😏 😒 🙄 😬 🤥 😌 😔 😪 🤤 😴 😷 🤒 🤕 🤢 🤮 🤧 🥵 🥶 🥴 😵 🤯 🤠 🥳 😎 🤓 🧐 😕 😟 🙁 ☹️ 😮 😯 😲 😳 🥺 😦 😧 😨 😰 😥 😢 😭 😱 😖 😣 😞 😓 😩 😫 🥱 😤 😡 😠 🤬 😈 👿 💀 ☠️ 💩 🤡 👹 👺 👻 👽 👾 🤖 😺 😸 😹 😻 😼 😽 🙀 😿 😾'),
  _e('👋 🤚 🖐️ ✋ 🖖 👌 🤌 🤏 ✌️ 🤞 🤟 🤘 🤙 👈 👉 👆 👇 ☝️ 👍 👎 ✊ 👊 🤛 🤜 👏 🙌 👐 🤲 🤝 🙏 ✍️ 💅 🤳 💪 🦾 👀 👁️ 👅 👄 🧠 👶 🧒 👦 👧 🧑 👨 👩 🧓 👴 👵 🙍 🙎 🙅 🙆 💁 🙋 🙇 🤦 🤷 👮 💂 👷 🤴 👸 🎅 🤶 🦸 🦹 🧙 🧚 🧛 🧜 🧝 🧞 🧟 💃 🕺 👯 🚶 🏃'),
  _e('🐶 🐱 🐭 🐹 🐰 🦊 🐻 🐼 🐨 🐯 🦁 🐮 🐷 🐸 🐵 🙈 🙉 🙊 🐔 🐧 🐦 🐤 🦆 🦅 🦉 🦇 🐺 🐗 🐴 🦄 🐝 🐛 🦋 🐌 🐞 🐜 🐢 🐍 🦎 🐙 🦑 🦐 🦀 🐡 🐠 🐟 🐬 🐳 🐋 🦈 🐊 🐅 🐆 🦓 🦍 🐘 🦛 🦏 🐪 🐫 🦒 🦘 🐃 🐂 🐄 🐎 🐖 🐏 🐑 🦙 🐐 🦌 🐕 🐩 🐈 🐓 🦃 🦚 🦜 🦢 🕊️ 🐇 🐿️ 🌵 🎄 🌲 🌳 🌴 🌱 🌿 ☘️ 🍀 🍁 🍂 🍃 🌺 🌻 🌹 🌷 🌼 🌸 💐 🍄 🌾 🌍 🌙 ⭐ 🌟 ✨ ⚡ 🔥 🌈 ☀️ ⛅ ☁️ 🌧️ ⛄ ❄️ 💧 🌊'),
  _e('🍏 🍎 🍐 🍊 🍋 🍌 🍉 🍇 🍓 🫐 🍈 🍒 🍑 🥭 🍍 🥥 🥝 🍅 🍆 🥑 🥦 🥕 🌽 🌶️ 🥔 🍠 🥐 🍞 🥖 🧀 🥚 🍳 🥞 🧇 🥓 🥩 🍗 🍖 🌭 🍔 🍟 🍕 🥪 🌮 🌯 🥗 🍝 🍜 🍲 🍛 🍣 🍱 🥟 🍤 🍙 🍚 🍘 🍥 🥠 🍢 🍡 🍧 🍨 🍦 🥧 🧁 🍰 🎂 🍮 🍭 🍬 🍫 🍿 🍩 🍪 🌰 🥜 🍯 🥛 ☕ 🍵 🧃 🥤 🍶 🍺 🍻 🥂 🍷 🥃 🍸 🍹 🍾 🧊 🍽️'),
  _e('⚽ 🏀 🏈 ⚾ 🥎 🎾 🏐 🏉 🎱 🏓 🏸 🥅 🏒 🏑 🏏 ⛳ 🏹 🎣 🥊 🥋 ⛸️ 🎿 🏂 🏋️ 🤸 ⛹️ 🤺 🏇 🧘 🏄 🏊 🚣 🚴 🏆 🥇 🥈 🥉 🏅 🎖️ 🎫 🎟️ 🎪 🎭 🎨 🎬 🎤 🎧 🎼 🎹 🥁 🎷 🎺 🎸 🎻 🎲 ♟️ 🎯 🎳 🎮 🎰 🧩'),
  _e('🚗 🚕 🚙 🚌 🚎 🏎️ 🚓 🚑 🚒 🚐 🚚 🚛 🚜 🛵 🏍️ 🚲 🛴 🚨 🚔 🚍 🚘 🚖 🚡 🚠 🚟 🚃 🚋 🚞 🚝 🚄 🚅 🚈 🚂 🚆 🚇 🚊 🚉 ✈️ 🛫 🛬 🚀 🛸 🚁 ⛵ 🚤 🛥️ 🚢 ⚓ ⛽ 🚧 🚦 🗺️ 🗿 🗽 🗼 🏰 🏯 🏟️ 🎡 🎢 🎠 ⛲ 🏖️ 🏝️ 🏜️ 🌋 ⛰️ 🏔️ 🗻 🏕️ ⛺ 🏠 🏡 🏢 🏥 🏦 🏨 🏪 🏫 🕌 🕍 ⛪ 🕋 ⛩️'),
  _e('⌚ 📱 💻 ⌨️ 🖥️ 🖨️ 🖱️ 💽 💾 💿 📷 📸 📹 🎥 📞 ☎️ 📺 📻 🎙️ ⏰ ⏳ 📡 🔋 🔌 💡 🔦 🕯️ 🧯 💸 💵 💴 💶 💷 💰 💳 💎 ⚖️ 🔧 🔨 ⚒️ 🛠️ ⛏️ 🔩 ⚙️ 🧱 ⛓️ 🧲 🔫 💣 🧨 🔪 🗡️ ⚔️ 🛡️ 🔮 📿 💈 ⚗️ 🔭 🔬 🩺 💊 💉 🩸 🧬 🦠 🧫 🧪 🌡️ 🧹 🧺 🧻 🚽 🚿 🛁 🧼 🧽 🔑 🗝️ 🚪 🛋️ 🛏️ 🧸 🎁 🎈 🎀 🎊 🎉 🎎 🏮 ✉️ 📦 📜 📃 📄 📊 📈 📉 📅 📌 📎 📏 📐 ✂️ 🔒 🔓 📝 ✏️ 🖊️ 🖌️ 🔍'),
  _e('❤️ 🧡 💛 💚 💙 💜 🖤 🤍 🤎 💔 ❣️ 💕 💞 💓 💗 💖 💘 💝 💟 ☮️ ✝️ ☪️ 🕉️ ☸️ ✡️ 🔯 🕎 ☯️ ♈ ♉ ♊ ♋ ♌ ♍ ♎ ♏ ♐ ♑ ♒ ♓ 🆔 ⚛️ ✅ ❌ ❎ ➕ ➖ ➗ ✖️ ♾️ ‼️ ⁉️ ❓ ❔ ❕ ❗ 〰️ 💯 🔴 🟠 🟡 🟢 🔵 🟣 ⚫ ⚪ 🟤 🔺 🔻 🔶 🔷 🔸 🔹 ▶️ ⏸️ ⏹️ ⏺️ ⏭️ ⏮️ ⏩ ⏪ 🔀 🔁 🔂 🔼 🔽 ➡️ ⬅️ ⬆️ ⬇️ ↗️ ↘️ ↙️ ↖️ ↕️ ↔️ ✔️ ☑️ 🔔 🔕 🔊 🔇 🏳️ 🏴 🏁 🚩 ♻️ ⚠️ 🚫 ⭕ 🆗 🆒 🆕 🆓 🔝 🔜 🔚'),
  _e('🇧🇩 🇮🇳 🇸🇦 🇵🇰 🇦🇪 🇶🇦 🇰🇼 🇴🇲 🇲🇾 🇸🇬 🇮🇩 🇹🇷 🇪🇬 🇺🇸 🇬🇧 🇨🇦 🇦🇺 🇩🇪 🇫🇷 🇮🇹 🇪🇸 🇯🇵 🇰🇷 🇨🇳 🇷🇺 🇧🇷'),
];

const List<IconData> kEmojiCatIcons = [
  Icons.emoji_emotions_outlined,
  Icons.waving_hand_outlined,
  Icons.pets_outlined,
  Icons.fastfood_outlined,
  Icons.sports_soccer_outlined,
  Icons.directions_car_outlined,
  Icons.lightbulb_outline,
  Icons.favorite_border,
  Icons.flag_outlined,
];

/// Built-in sticker pack: big emoji, nothing to download.
final List<String> kEmojiStickers = _e('😂 😍 🥰 😘 😎 🤩 😭 😡 🥺 🤗 😴 🤔 🙄 😱 🤯 🥳 👍 👏 🙏 💪 🔥 ❤️ 💔 🎉 💯 ✨ 🌹 😅 🤝 👌 😇 🤣');

// ---- the panel ----------------------------------------------------------------------------------------------------

class EmojiStickerPanel extends StatefulWidget {
  final ValueChanged<String> onEmoji;
  final VoidCallback onBackspace;
  final void Function(String pack, String file) onSticker;
  const EmojiStickerPanel({super.key, required this.onEmoji, required this.onBackspace, required this.onSticker});
  @override
  State<EmojiStickerPanel> createState() => _ESP();
}

class _ESP extends State<EmojiStickerPanel> {
  int tab = 0, cat = 0, pack = 0; // tab 0 = emoji, 1 = stickers; pack 0 = built-in emoji stickers
  List<String> recent = [];
  Timer? bsTimer;

  @override
  void initState() {
    super.initState();
    recent = loadRecent();
    refreshStickerPacks().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    bsTimer?.cancel();
    super.dispose();
  }

  List<String> loadRecent() => prefs.getStringList(pk('recentEmoji')) ?? <String>[];

  void pushRecent(String e) {
    final l = List<String>.from(loadRecent())
      ..remove(e)
      ..insert(0, e);
    prefs.setStringList(pk('recentEmoji'), l.take(24).toList());
  }

  Widget segment(BuildContext c) {
    final cs = Theme.of(c).colorScheme;
    Widget label(int i, String text) => Expanded(
        child: PressScale(
            scale: .96,
            onTap: () => setState(() => tab = i),
            child: Center(child: AnimatedDefaultTextStyle(duration: const Duration(milliseconds: 180), style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: tab == i ? cs.onPrimaryContainer : cs.onSurfaceVariant), child: Text(text)))));
    return Container(
        height: 38,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(20)),
        child: Stack(children: [
          AnimatedAlign(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: tab == 0 ? Alignment.centerLeft : Alignment.centerRight,
              child: FractionallySizedBox(widthFactor: .5, heightFactor: 1, child: Container(decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(17))))),
          Row(children: [label(0, t(c, 'emojiTab')), label(1, t(c, 'stickerTab'))]),
        ]));
  }

  Widget backspace(BuildContext c) {
    final cs = Theme.of(c).colorScheme;
    return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onBackspace,
        onLongPressStart: (_) => bsTimer = Timer.periodic(const Duration(milliseconds: 70), (_) => widget.onBackspace()),
        onLongPressEnd: (_) => bsTimer?.cancel(),
        onLongPressCancel: () => bsTimer?.cancel(),
        child: Container(width: 46, height: 38, alignment: Alignment.center, child: Icon(Icons.backspace_outlined, color: cs.onSurfaceVariant, size: 23)));
  }

  Widget emojiGrid(List<String> list) => GridView.builder(
      key: ValueKey('e$cat'),
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 46, mainAxisExtent: 46),
      itemCount: list.length,
      itemBuilder: (_, i) => PressScale(
          scale: .78,
          onTap: () {
            widget.onEmoji(list[i]);
            pushRecent(list[i]);
          },
          child: Center(child: Text(list[i], style: const TextStyle(fontSize: 27)))));

  Widget stickerGrid(BuildContext c, List packs) {
    final cs = Theme.of(c).colorScheme;
    final builtin = pack == 0;
    final Map pp = builtin ? const {} : packs[pack - 1] as Map;
    final items = builtin ? kEmojiStickers : (pp['items'] as List).map((e) => '$e').toList();
    final id = '${pp['id']}';
    return Column(key: ValueKey('s$pack'), crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
          child: Text(builtin ? t(c, 'stickerBuiltin') : packTitle(pp), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant))),
      Expanded(
          child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: builtin ? 84 : 96, mainAxisSpacing: 4, crossAxisSpacing: 4),
              itemCount: items.length,
              itemBuilder: (_, i) => PressScale(
                  scale: .85,
                  onTap: () => widget.onSticker(builtin ? 'emoji' : id, items[i]),
                  child: Center(child: builtin ? Text(items[i], style: const TextStyle(fontSize: 46)) : StickerImg(stickerUrl(id, items[i]), size: 78))))),
    ]);
  }

  Widget bottomBar(BuildContext c, List<IconData> icons, List packs) {
    final cs = Theme.of(c).colorScheme;
    Widget chip(bool sel, Widget child, VoidCallback f) => PressScale(
        onTap: f,
        child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 42,
            height: 38,
            margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
            decoration: BoxDecoration(color: sel ? cs.primaryContainer : Colors.transparent, borderRadius: BorderRadius.circular(12)),
            child: Center(child: child)));
    return SizedBox(
        height: 48,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 8), children: [
          if (tab == 0)
            for (var i = 0; i < icons.length; i++) chip(cat == i, Icon(icons[i], size: 22, color: cat == i ? cs.primary : cs.onSurfaceVariant), () => setState(() => cat = i))
          else ...[
            chip(pack == 0, const Text('😀', style: TextStyle(fontSize: 22)), () => setState(() => pack = 0)),
            for (var i = 0; i < packs.length; i++) chip(pack == i + 1, StickerImg(stickerUrl('${packs[i]['id']}', '${packs[i]['icon']}'), size: 28), () => setState(() => pack = i + 1)),
          ],
        ]));
  }

  @override
  Widget build(BuildContext c) {
    final cs = Theme.of(c).colorScheme;
    final cats = <List<String>>[if (recent.isNotEmpty) recent, ...kEmojiCats];
    final icons = <IconData>[if (recent.isNotEmpty) Icons.history_rounded, ...kEmojiCatIcons];
    if (cat >= cats.length) cat = 0;
    final packs = kStickerPacks;
    if (pack > packs.length) pack = 0;
    return Container(
        decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            border: Border(top: BorderSide(color: cs.outlineVariant.withOpacity(.4)))),
        child: Column(children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 2),
              child: Row(children: [
                Expanded(child: Align(alignment: AlignmentDirectional.centerStart, child: SizedBox(width: 230, child: segment(c)))),
                if (tab == 0) backspace(c),
              ])),
          Expanded(child: AnimatedSwitcher(duration: const Duration(milliseconds: 200), child: tab == 0 ? emojiGrid(cats[cat]) : stickerGrid(c, packs))),
          bottomBar(c, icons, packs),
        ]));
  }
}
