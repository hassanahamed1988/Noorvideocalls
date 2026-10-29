// Contact Info: the page that opens when you tap another user's profile inside a chat.
//
//   Manage Storage · Media visibility · Notifications · Message timer · Privacy Chat · Chat Lock ·
//   Calls Privacy · Permission · Clear Chat History · Report · Block · Delete Contact
//
// Where each setting lives:
//   * Permission (per contact, set by me)      -> server  POST /contact/settings   (enforced by the server)
//   * Privacy Chat / call shield / call E2E    -> server  POST /dm/settings        (shared by both people of the chat)
//   * Media visibility, Notifications          -> this phone only (SharedPreferences, key = ..._<chatId>)
//   * Message timer                            -> server  POST /chats/timer        (already existed)
import 'dart:async';
import 'dart:math' show pi;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'main.dart';

/// Native helper (MainActivity.kt): system ringtone picker + playing a chosen sound.
const _soundCh = MethodChannel('noor/sound');

/// The chat that is on screen right now (set by ChatPage). Used to skip popups for it.
String? openChatId;

Future<Map> ciSettings(String phone) async {
  final r = await getj('/contact/settings?phone=${Uri.encodeQueryComponent(phone)}');
  return r is Map ? r : {};
}

Future<bool?> _ciConfirm(BuildContext c, String title, String body, String action) => showDialog<bool>(
    context: c,
    builder: (ctx) => AlertDialog(title: Text(title), content: Text(body), actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t(ctx, 'cancel'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(action, style: TextStyle(color: Theme.of(ctx).colorScheme.error))),
        ]));

/// Message timer for one chat (same options the chat menu always had).
Future<void> chooseChatTimer(BuildContext context, String id) async {
  try {
    final r = await getj('/chats/timer?chat=${Uri.encodeQueryComponent(id)}');
    if (r is! Map || !context.mounted) return;
    final glob = '${r['global'] ?? 0}';
    final names = {
      '86400000': t(context, 'h24'),
      '604800000': t(context, 'd7'),
      '2592000000': t(context, 't1m'),
      '5184000000': t(context, 't2m'),
      '7776000000': t(context, 't90'),
      '0': t(context, 'timerOff'),
    };
    final opts = {'default': '${t(context, 'timerDefault')} (${names[glob] ?? t(context, 'timerOff')})', ...names};
    final v = await pickOption(context, t(context, 'msgTimer'), '${r['value']}', opts);
    if (v == null) return;
    await post('/chats/timer', {'chat': id, 'timer': v == 'default' ? 'default' : int.parse(v)});
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(context, 'timerSaved'))));
  } catch (_) {}
}

// =====================================================================================
// Contact Info page
// =====================================================================================
class ContactInfoPage extends StatefulWidget {
  final String phone;
  final String name;
  final String? avatar;
  const ContactInfoPage(this.phone, {this.name = '', this.avatar, super.key});
  @override
  State<ContactInfoPage> createState() => _CI();
}

class _CI extends State<ContactInfoPage> {
  Map s = {};

  String get chat => dm(me, widget.phone);
  String get name => '${s['name'] ?? widget.name}';
  Map get dmS => (s['dm'] as Map?) ?? {};
  bool get isBlocked => s['blocked'] == true;

  @override
  void initState() {
    super.initState();
    load();
    msgTick.addListener(load);
  }

  @override
  void dispose() {
    msgTick.removeListener(load);
    super.dispose();
  }

  Future<void> load() async {
    try {
      final r = await ciSettings(widget.phone);
      if (mounted && r.isNotEmpty) setState(() => s = r);
    } catch (_) {}
  }

  void snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  void home() {
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<void> setPriv(bool v) async {
    setState(() => s['dm'] = {...dmS, 'priv': v});
    final r = await post('/dm/settings', {'chat': chat, 'priv': v});
    if (r['error'] != null) load();
  }

  Future<void> toggleLock(bool v) async {
    final u = {'name': name, 'phone': widget.phone, 'avatar': s['avatar'] ?? widget.avatar};
    if (v) {
      final ok = await showDialog<bool>(context: context, barrierDismissible: false, builder: (_) => ChatLockDialog(Map.from(u)));
      if (ok == true && mounted) {
        msgTick.value++;
        storyTick.value++;
        snack(t(context, 'lockedOn'));
        home(); // a locked chat is hidden from the lists, so go back to the start page
      }
    } else {
      final r = await deviceAuth(context, t(context, 'unlockReason'));
      if (r == AuthResult.failed) return snack(t(context, 'authFailed'));
      await post('/chatlock/remove', {'phone': widget.phone});
      if (!mounted) return;
      setState(() => s['chatLocked'] = false);
      msgTick.value++;
      storyTick.value++;
      snack(t(context, 'lockedOff'));
    }
  }

  Future<void> clearChat() async {
    final ok = await _ciConfirm(context, t(context, 'clearQ'), t(context, 'clearInfo'), t(context, 'clearChat'));
    if (ok != true) return;
    await post('/messages/clear', {'chat': chat});
    msgTick.value++;
    snack(t(context, 'clearDone'));
  }

  Future<void> report() async {
    final res = await showDialog<Map>(context: context, builder: (_) => const _ReportDialog());
    if (res == null) return;
    final text = '${res['text']}';
    await post('/report', {'phone': widget.phone, 'reason': text.isEmpty ? '${res['reason']}' : '${res['reason']}: $text'});
    if (!mounted) return;
    snack(t(context, 'reportSent'));
    if (res['block'] == true) {
      await post('/block', {'phone': widget.phone, 'on': true});
      msgTick.value++;
      home();
    }
  }

  Future<void> toggleBlock() async {
    if (!isBlocked) {
      final ok = await _ciConfirm(context, t(context, 'blockQ'), t(context, 'blockedInfo'), t(context, 'block'));
      if (ok != true) return;
      await post('/block', {'phone': widget.phone, 'on': true});
      msgTick.value++;
      snack(t(context, 'blockDone'));
      home();
    } else {
      await post('/block', {'phone': widget.phone, 'on': false});
      if (!mounted) return;
      setState(() => s['blocked'] = false);
      msgTick.value++;
      snack(t(context, 'unblockDone'));
    }
  }

  Future<void> deleteContact() async {
    final ok = await _ciConfirm(context, t(context, 'delQ'), t(context, 'delInfo'), t(context, 'deleteContact'));
    if (ok != true) return;
    await post('/contacts/remove', {'phone': widget.phone});
    msgTick.value++;
    storyTick.value++;
    snack(t(context, 'delDone'));
    home();
  }

  @override
  Widget build(BuildContext c) {
    final cs = Theme.of(c).colorScheme;
    void go(Widget page) => Navigator.push(c, MaterialPageRoute(builder: (_) => page)).then((_) => load());
    Widget nav(IconData ic, String key, VoidCallback on) =>
        ListTile(leading: Icon(ic), title: Text(t(c, key)), trailing: const Icon(Icons.chevron_right), onTap: on);
    Widget danger(IconData ic, String label, VoidCallback on) =>
        ListTile(leading: Icon(ic, color: cs.error), title: Text(label, style: TextStyle(color: cs.error)), onTap: on);
    return CoverScaffold(
        title: t(c, 'ciTitle'),
        header: ProfileHeader(name, cover: s['cover'], avatar: s['avatar'] ?? widget.avatar, ring: pageBg(c)),
        children: [
          const SizedBox(height: 12),
          Center(child: Text(name, style: Theme.of(c).textTheme.headlineSmall)),
          Center(child: Text(widget.phone, style: Theme.of(c).textTheme.bodyMedium?.copyWith(color: cs.outline))),
          const SizedBox(height: 8),
          SectionCard([
            nav(Icons.person_outline, 'viewProfile', () => go(ProfilePage(widget.phone))),
          ]),
          SectionCard([
            nav(Icons.storage_outlined, 'manageStorage', () => go(ManageStoragePage(chat))),
            nav(Icons.photo_library_outlined, 'mediaVis', () => showMediaVisibility(c, chat)),
            nav(Icons.notifications_outlined, 'notifications', () => go(NotificationsPage(chat))),
            nav(Icons.timer_outlined, 'msgTimer', () => chooseChatTimer(c, chat)),
            ListTile(
                leading: const Icon(Icons.privacy_tip_outlined),
                title: Text(t(c, 'privacyChat')),
                trailing: Switch(value: dmS['priv'] == true, onChanged: setPriv),
                onTap: () => go(PrivacyChatPage(chat))),
            if (s['isContact'] != false)
              SwitchListTile(
                  secondary: const Icon(Icons.lock_outline),
                  title: Text(t(c, 'chatLock')),
                  subtitle: Text(t(c, 'chatLockInfo')),
                  value: s['chatLocked'] == true,
                  onChanged: toggleLock),
            nav(Icons.shield_outlined, 'callsPrivacy', () => go(CallsPrivacyPage(chat))),
            nav(Icons.admin_panel_settings_outlined, 'permission', () => go(PermissionPage(widget.phone))),
          ]),
          SectionCard([
            danger(Icons.delete_sweep_outlined, t(c, 'clearChat'), clearChat),
            danger(Icons.flag_outlined, t(c, 'report'), report),
            danger(Icons.block, isBlocked ? t(c, 'unblock') : t(c, 'block'), toggleBlock),
            if (s['isContact'] != false) danger(Icons.person_remove_outlined, t(c, 'deleteContact'), deleteContact),
          ]),
        ]);
  }
}

class _ReportDialog extends StatefulWidget {
  const _ReportDialog();
  @override
  State<_ReportDialog> createState() => _RD();
}

class _RD extends State<_ReportDialog> {
  String reason = 'spam';
  bool block = false;
  final tc = TextEditingController();

  @override
  void dispose() {
    tc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final reasons = {'spam': t(c, 'rSpam'), 'abuse': t(c, 'rAbuse'), 'fake': t(c, 'rFake'), 'scam': t(c, 'rScam'), 'other': t(c, 'rOther')};
    return AlertDialog(
        title: Text(t(c, 'reportQ')),
        content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          ...reasons.entries.map((e) => RadioListTile<String>(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(e.value),
              value: e.key,
              groupValue: reason,
              onChanged: (v) => setState(() => reason = v ?? reason))),
          AppInput(controller: tc, hint: t(c, 'rDetails'), maxLines: 3, minLines: 1, margin: const EdgeInsets.only(top: 8)),
          CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(t(c, 'alsoBlock')),
              value: block,
              onChanged: (v) => setState(() => block = v == true)),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(t(c, 'cancel'))),
          FilledButton(onPressed: () => Navigator.pop(c, {'reason': reason, 'text': tc.text.trim(), 'block': block}), child: Text(t(c, 'sendBtn'))),
        ]);
  }
}

// =====================================================================================
// Permission
// =====================================================================================
/// Switch semantics (all stored on the server, per contact):
///   Calls Me / Last Seen & Online Status / Input Status / Read receipts: ON = allowed (default ON)
///   Video Calls / Audio Calls / Chat message: ON = I cannot do it to this user (default OFF)
class PermissionPage extends StatefulWidget {
  final String phone;
  const PermissionPage(this.phone, {super.key});
  @override
  State<PermissionPage> createState() => _PM();
}

class _PM extends State<PermissionPage> {
  Map p = {};

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = await ciSettings(widget.phone);
      if (mounted && r['perms'] is Map) setState(() => p = Map.from(r['perms']));
    } catch (_) {}
  }

  bool on(String k, bool def) => p[k] is bool ? p[k] as bool : def;

  Future<void> set(String k, bool v) async {
    setState(() => p[k] = v);
    final r = await post('/contact/settings', {'phone': widget.phone, k: v});
    if (r['error'] != null && mounted) setState(() => p[k] = !v);
  }

  @override
  Widget build(BuildContext c) {
    Widget sw(String k, bool def, String title, {String? sub}) =>
        SwitchListTile(title: Text(title), subtitle: sub == null ? null : Text(sub, style: Theme.of(c).textTheme.bodySmall), value: on(k, def), onChanged: (v) => set(k, v));
    return Scaffold(
        backgroundColor: pageBg(c),
        appBar: AppBar(title: Text(t(c, 'permission')), backgroundColor: pageBg(c)),
        body: ListView(padding: bp(c, top: 4, card: true), children: [
          SectionCard([
            sw('callsMe', true, t(c, 'callsMe'), sub: t(c, 'callsMeInfo')),
            sw('lastSeen', true, t(c, 'lastSeenOpt')),
            sw('typing', true, t(c, 'inputStatus')),
            sw('read', true, t(c, 'readRec')),
            sw('vidOut', false, t(c, 'videoCalls')),
            sw('audOut', false, t(c, 'audioCalls')),
            sw('msgOut', false, t(c, 'chatMessage')),
          ]),
        ]));
  }
}

// =====================================================================================
// Media visibility (bottom sheet with Yes / No)
// =====================================================================================
Future<void> showMediaVisibility(BuildContext c, String chat) =>
    showModalBottomSheet<void>(context: c, backgroundColor: Colors.transparent, useSafeArea: true, builder: (_) => _MediaVisSheet(chat));

class _MediaVisSheet extends StatefulWidget {
  final String chat;
  const _MediaVisSheet(this.chat);
  @override
  State<_MediaVisSheet> createState() => _MVS();
}

class _MVS extends State<_MediaVisSheet> {
  // No choice made for this chat yet -> follow Settings > Media
  bool get yes {
    final v = prefs.getString('mediaVis_${widget.chat}');
    if (v != null) return v == 'yes';
    return prefs.getBool('autoSavePhotos') == true || prefs.getBool('autoSaveVideos') == true;
  }

  Future<void> setYes(bool v) async {
    await prefs.setString('mediaVis_${widget.chat}', v ? 'yes' : 'no');
    if (v) await prefs.setInt('mediaVisSince_${widget.chat}', DateTime.now().millisecondsSinceEpoch);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext c) {
    final cs = Theme.of(c).colorScheme;
    return Material(
        color: cs.surfaceContainerLow,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
            top: false,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(height: 10),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: cs.onSurface.withOpacity(.6), borderRadius: BorderRadius.circular(2))),
              Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                  child: Text(t(c, 'mediaVisQ'), style: TextStyle(fontSize: 13.5, height: 1.35, color: cs.onSurfaceVariant))),
              const Divider(height: 1),
              SwitchListTile(title: Text(t(c, 'yes'), style: const TextStyle(fontSize: 15)), value: yes, onChanged: (v) => setYes(v)),
              SwitchListTile(title: Text(t(c, 'no'), style: const TextStyle(fontSize: 15)), value: !yes, onChanged: (v) => setYes(!v)),
              const SizedBox(height: 8),
            ])));
  }
}

// =====================================================================================
// Manage Storage: Send | Receive  x  Photos, Videos, Voice, Documents, Links
// =====================================================================================
class ManageStoragePage extends StatefulWidget {
  final String chat;
  const ManageStoragePage(this.chat, {super.key});
  @override
  State<ManageStoragePage> createState() => _MSP();
}

class _MSP extends State<ManageStoragePage> with SingleTickerProviderStateMixin {
  late final TabController tab = TabController(length: 2, vsync: this); // swipe / tap = smooth slide
  static const cats = ['photos', 'videos', 'voiceMsgs', 'documents', 'links'];
  static const catIcons = [Icons.photo_outlined, Icons.videocam_outlined, Icons.mic_none, Icons.insert_drive_file_outlined, Icons.link];
  static final urlRe = RegExp(r'(https?:\/\/[^\s]+|www\.[^\s]+)', caseSensitive: false);
  List msgs = [];
  bool loaded = false;
  int cat = 0;
  String query = '';
  final q = TextEditingController();

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    tab.dispose();
    q.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final r = await getj('/messages?chat=${Uri.encodeQueryComponent(widget.chat)}');
      if (mounted && r is List) {
        setState(() {
          msgs = r;
          loaded = true;
        });
      }
    } catch (_) {}
  }

  bool match(String s) => query.isEmpty || s.toLowerCase().contains(query.toLowerCase());

  List items(bool sent) {
    final out = [];
    for (final m in msgs) {
      if (m is! Map) continue;
      if ((m['from'] == me) != sent) continue;
      final type = '${m['type'] ?? 'text'}';
      if (cat == 0 && type == 'image') out.add(m);
      if (cat == 1 && type == 'video') out.add(m);
      if (cat == 2 && type == 'voice') out.add(m);
      if (cat == 3 && type == 'document' && match('${m['text'] ?? ''}')) out.add(m);
      if (cat == 4 && type == 'text') {
        for (final x in urlRe.allMatches('${m['text']}')) {
          final l = x.group(0) ?? '';
          if (l.isNotEmpty && match(l)) out.add({'link': l, 'ts': m['ts']});
        }
      }
    }
    return out.reversed.toList();
  }

  Widget view(BuildContext c, bool sent) {
    final cs = Theme.of(c).colorScheme;
    if (!loaded) return const Center(child: CircularProgressIndicator());
    final list = items(sent);
    if (list.isEmpty) return emptyState(c, catIcons[cat], t(c, 'nothingHere'));
    if (cat == 0 || cat == 1) {
      final video = cat == 1;
      return GridView.builder(
          padding: bp(c, top: 8, h: 8),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 4, crossAxisSpacing: 4),
          itemCount: list.length,
          itemBuilder: (_, i) {
            final m = list[i] as Map;
            return GestureDetector(
                onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => MediaViewer('${m['url']}', video))),
                child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: video
                        ? Container(color: Colors.black87, child: const Center(child: Icon(Icons.play_circle_fill, color: Colors.white, size: 36)))
                        : Image.network('$base${m['url']}', fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_outlined)))));
          });
    }
    return ListView.builder(
        padding: bp(c, top: 4),
        itemCount: list.length,
        itemBuilder: (_, i) {
          final m = list[i] as Map;
          if (cat == 2) {
            return Container(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
                child: VoiceBubble(m));
          }
          if (cat == 4) {
            return ListTile(
                leading: const Icon(Icons.link),
                title: Text('${m['link']}', maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: m['ts'] == null ? null : Text(fmtFull(m['ts'] as num)),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: '${m['link']}'));
                  ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(t(c, 'copied'))));
                });
          }
          return ListTile(
              leading: const Icon(Icons.insert_drive_file_outlined),
              title: Text('${m['text'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: m['ts'] == null ? null : Text(fmtFull(m['ts'] as num)));
        });
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        backgroundColor: pageBg(c),
        appBar: AppBar(title: Text(t(c, 'manageStorage')), backgroundColor: pageBg(c)),
        body: Column(children: [
          TabBar(controller: tab, tabs: [Tab(text: t(c, 'send')), Tab(text: t(c, 'receive'))]),
          SizedBox(
              height: 54,
              child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), children: [
                for (var i = 0; i < cats.length; i++)
                  Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: ChoiceChip(
                          label: Text(t(c, cats[i])),
                          selected: cat == i,
                          onSelected: (_) => setState(() {
                                cat = i;
                                query = '';
                                q.clear();
                              }))),
              ])),
          AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              child: cat >= 3
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: AppInput(
                          controller: q,
                          icon: Icons.search,
                          hint: t(c, cat == 3 ? 'searchDocs' : 'searchLinks'),
                          onChanged: (v) => setState(() => query = v.trim())))
                  : const SizedBox(width: double.infinity)),
          Expanded(child: TabBarView(controller: tab, children: [view(c, true), view(c, false)])),
        ]),
      );
}

// =====================================================================================
// Notifications (stored on this phone, per chat)
// =====================================================================================
Future<Map?> _pickSound(String type, String? cur) async {
  try {
    return await _soundCh.invokeMethod<Map>('pick', {'type': type, 'uri': cur == 'silent' ? null : cur});
  } catch (_) {
    return null;
  }
}

class NotificationsPage extends StatefulWidget {
  final String chat;
  const NotificationsPage(this.chat, {super.key});
  @override
  State<NotificationsPage> createState() => _NP();
}

class _NP extends State<NotificationsPage> {
  String key(String k) => 'n${k}_${widget.chat}'; // nMute_, nTone_, nToneName_, nPopup_, nRing_, nRingName_
  bool get mute => prefs.getBool(key('Mute')) ?? false;
  bool get popup => prefs.getBool(key('Popup')) ?? true;
  String soundName(String k) {
    final n = prefs.getString(key('${k}Name'));
    return (n == null || n.isEmpty) ? t(context, 'toneDefault') : n;
  }

  Future<void> pick(String k) async {
    final silent = t(context, 'toneSilent');
    final r = await _pickSound(k == 'Ring' ? 'ringtone' : 'notification', prefs.getString(key(k)));
    if (r == null) return;
    final uri = r['uri'];
    await prefs.setString(key(k), uri == null ? 'silent' : '$uri');
    await prefs.setString(key('${k}Name'), uri == null ? silent : '${r['name'] ?? ''}');
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        backgroundColor: pageBg(c),
        appBar: AppBar(title: Text(t(c, 'notifications')), backgroundColor: pageBg(c)),
        body: ListView(padding: bp(c, top: 4, card: true), children: [
          SectionCard([
            SwitchListTile(
                title: Text(t(c, 'mute')),
                value: mute,
                onChanged: (v) async {
                  await prefs.setBool(key('Mute'), v);
                  setState(() {});
                }),
            ListTile(title: Text(t(c, 'notifTone')), subtitle: Text(soundName('Tone')), trailing: const Icon(Icons.chevron_right), onTap: () => pick('Tone')),
            SwitchListTile(
                title: Text(t(c, 'popupNotif')),
                value: popup,
                onChanged: (v) async {
                  await prefs.setBool(key('Popup'), v);
                  setState(() {});
                }),
            ListTile(title: Text(t(c, 'callRingtone')), subtitle: Text(soundName('Ring')), trailing: const Icon(Icons.chevron_right), onTap: () => pick('Ring')),
          ]),
        ]),
      );
}

// ---- in-app popup + sounds (called from Home's socket handlers) -------------------------
final _nameCache = <String, Map>{};
OverlayEntry? _banner;
Timer? _bannerTimer;

void _hideBanner() {
  _bannerTimer?.cancel();
  _banner?.remove();
  _banner = null;
}

/// A new message arrived. Shows the popup and/or plays the tone chosen for that chat (unless muted
/// or that chat is already open).
Future<void> onIncomingMessage(dynamic d) async {
  try {
    if (d is! Map) return;
    final chat = d['chat'], from = d['from'];
    if (chat is! String || from is! String || from == me) return;
    if (d['read'] == true || d['dm'] == true || d['erased'] == true) return;
    if (chat == openChatId) return;
    if (prefs.getBool('nMute_$chat') == true) return;
    final tone = prefs.getString('nTone_$chat');
    if (tone != null && tone != 'silent') {
      try {
        await _soundCh.invokeMethod('play', {'type': 'notification', 'uri': tone, 'loop': false});
      } catch (_) {}
    }
    if (prefs.getBool('nPopup_$chat') ?? true) await _showBanner(chat, from, d);
  } catch (_) {}
}

Future<void> _showBanner(String chat, String from, Map d) async {
  var info = _nameCache[from];
  if (info == null) {
    final r = await getj('/profile?phone=${Uri.encodeQueryComponent(from)}');
    if (r is Map && r['name'] != null) {
      info = r;
      _nameCache[from] = r;
    }
  }
  final ctx = navKey.currentContext;
  final overlay = navKey.currentState?.overlay;
  if (ctx == null || overlay == null) return;
  final name = '${info?['name'] ?? from}';
  final type = '${d['type'] ?? 'text'}';
  var body = '';
  if (type == 'image') {
    body = '📷 ${t(ctx, 'photo')}';
  } else if (type == 'video') {
    body = '🎥 ${t(ctx, 'video')}';
  } else if (type == 'voice') {
    body = '🎤 ${t(ctx, 'voiceMsg')}';
  } else {
    final r = await getj('/messages?chat=${Uri.encodeQueryComponent(chat)}');
    if (r is List) {
      for (final m in r.reversed) {
        if (m is Map && m['id'] == d['id']) {
          body = '${m['text'] ?? ''}';
          break;
        }
      }
    }
  }
  _hideBanner();
  final avatar = info?['avatar'];
  late final OverlayEntry entry;
  entry = OverlayEntry(builder: (oc) {
    final cs = Theme.of(oc).colorScheme;
    return Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: SafeArea(
            child: TweenAnimationBuilder<double>(
                tween: Tween(begin: -1, end: 0),
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                builder: (_, v, child) => FractionalTranslation(translation: Offset(0, v), child: child),
                child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Material(
                        elevation: 8,
                        color: cs.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () {
                              _hideBanner();
                              if (!chat.startsWith('g')) {
                                navKey.currentState?.push(MaterialPageRoute(builder: (_) => ChatPage({'chat': chat, 'title': name, 'peer': from, 'avatar': avatar})));
                              }
                            },
                            child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                child: Row(children: [
                                  Avatar(name, r: 20, url: avatar),
                                  const SizedBox(width: 12),
                                  Expanded(
                                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                                    Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                                    if (body.isNotEmpty) Text(body, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                                  ])),
                                ]))))))));
  });
  overlay.insert(entry);
  _banner = entry;
  _bannerTimer = Timer(const Duration(seconds: 4), () {
    if (_banner == entry) _hideBanner();
  });
}

/// Incoming call: ring with the ringtone picked for this caller (nothing is played if none was picked).
Future<void> startCallRing(dynamic phone) async {
  try {
    final cur = prefs.getString('nRing_${dm(me, '$phone')}');
    if (cur == null || cur == 'silent') return;
    await _soundCh.invokeMethod('play', {'type': 'ringtone', 'uri': cur, 'loop': true});
  } catch (_) {}
}

Future<void> stopCallRing() async {
  try {
    await _soundCh.invokeMethod('stop');
  } catch (_) {}
}

// =====================================================================================
// Privacy Chat (shared by both people of the chat)
// =====================================================================================
class PrivacyChatPage extends StatefulWidget {
  final String chat;
  const PrivacyChatPage(this.chat, {super.key});
  @override
  State<PrivacyChatPage> createState() => _PC();
}

class _PC extends State<PrivacyChatPage> {
  Map d = {};

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = await getj('/dm/settings?chat=${Uri.encodeQueryComponent(widget.chat)}');
      if (mounted && r is Map && r.isNotEmpty) setState(() => d = r);
    } catch (_) {}
  }

  Future<void> upd(Map<String, dynamic> body) async {
    setState(() => d = {...d, ...body});
    final r = await post('/dm/settings', {'chat': widget.chat, ...body});
    if (r['error'] != null) load();
  }

  @override
  Widget build(BuildContext c) {
    final cs = Theme.of(c).colorScheme;
    final on = d['priv'] == true;
    final tm = {'3600000': t(c, 'h1'), '86400000': t(c, 'h24'), '604800000': t(c, 'd7')};
    final small = Theme.of(c).textTheme.bodySmall;
    Widget feature(IconData ic, String title, String sub, {Widget? trailing, VoidCallback? onTap}) => ListTile(
        leading: Icon(ic, color: on ? cs.primary : cs.outline),
        title: Text(title),
        subtitle: Padding(padding: const EdgeInsets.only(top: 2), child: Text(sub, style: small)),
        trailing: trailing,
        onTap: onTap);
    final check = Icon(on ? Icons.check_circle : Icons.radio_button_unchecked, color: on ? cs.primary : cs.outline, size: 22);
    return Scaffold(
        backgroundColor: pageBg(c),
        appBar: AppBar(title: Text(t(c, 'privacyChat')), backgroundColor: pageBg(c)),
        body: ListView(padding: bp(c, top: 4, card: true), children: [
          SectionCard([
            SwitchListTile(secondary: const Icon(Icons.privacy_tip_outlined), title: Text(t(c, 'privacyChat')), value: on, onChanged: (v) => upd({'priv': v})),
          ]),
          SectionCard([
            feature(Icons.timer_outlined, t(c, 'pcDisappear'), t(c, 'pcDisappearInfo'),
                trailing: Text(tm['${d['timer'] ?? 86400000}'] ?? '', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600)), onTap: () async {
              final v = await pickOption(c, t(c, 'timer'), '${d['timer'] ?? 86400000}', tm);
              if (v != null) upd({'timer': int.parse(v)});
            }),
            feature(Icons.history_toggle_off, t(c, 'pcTime'), t(c, 'pcTimeInfo'), trailing: check),
            feature(Icons.enhanced_encryption_outlined, t(c, 'pcE2E'), t(c, 'pcE2EInfo'), trailing: check),
            feature(Icons.no_photography_outlined, t(c, 'pcShield'), t(c, 'pcShieldInfo'), trailing: check),
          ]),
        ]));
  }
}

// =====================================================================================
// Calls Privacy
// =====================================================================================
class CallsPrivacyPage extends StatelessWidget {
  final String chat;
  const CallsPrivacyPage(this.chat, {super.key});
  @override
  Widget build(BuildContext c) => Scaffold(
        backgroundColor: pageBg(c),
        appBar: AppBar(title: Text(t(c, 'callsPrivacy')), backgroundColor: pageBg(c)),
        body: ListView(padding: bp(c, top: 4, card: true), children: [
          SectionCard([
            ListTile(
                leading: const Icon(Icons.no_photography_outlined),
                title: Text(t(c, 'csShot')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => CallSettingPage(chat, true)))),
            ListTile(
                leading: const Icon(Icons.enhanced_encryption_outlined),
                title: Text(t(c, 'csE2E')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => CallSettingPage(chat, false)))),
          ]),
        ]),
      );
}

/// One call setting page: picture + short text + switch. shot = true: Block Screenshot for Calls, false: End-to-End Call Encryption.
class CallSettingPage extends StatefulWidget {
  final String chat;
  final bool shot;
  const CallSettingPage(this.chat, this.shot, {super.key});
  @override
  State<CallSettingPage> createState() => _CSP();
}

class _CSP extends State<CallSettingPage> {
  bool on = false;
  String get k => widget.shot ? 'callShot' : 'callE2E';

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = await getj('/dm/settings?chat=${Uri.encodeQueryComponent(widget.chat)}');
      if (mounted && r is Map) setState(() => on = r[k] == true);
    } catch (_) {}
  }

  Future<void> toggle(bool v) async {
    setState(() => on = v);
    final r = await post('/dm/settings', {'chat': widget.chat, k: v});
    if (r['error'] != null && mounted) setState(() => on = !v);
  }

  @override
  Widget build(BuildContext c) {
    final cs = Theme.of(c).colorScheme;
    final title = t(c, widget.shot ? 'csShot' : 'csE2E');
    return Scaffold(
        backgroundColor: pageBg(c),
        appBar: AppBar(title: Text(title), backgroundColor: pageBg(c)),
        body: ListView(padding: bp(c, top: 24, card: true), children: [
          Center(child: SizedBox(width: 260, height: 190, child: CustomPaint(painter: _CallArt(widget.shot, cs.primary, cs.primaryContainer, cs.outline, cs.error)))),
          Padding(
              padding: const EdgeInsets.fromLTRB(28, 12, 28, 20),
              child: Text(t(c, widget.shot ? 'csShotInfo' : 'csE2EInfo'), textAlign: TextAlign.center, style: TextStyle(fontSize: 13.5, height: 1.4, color: cs.onSurfaceVariant))),
          SectionCard([SwitchListTile(title: Text(title), value: on, onChanged: toggle)]),
        ]));
  }
}

/// The two pictures drawn in code (no image files needed).
class _CallArt extends CustomPainter {
  final bool shot;
  final Color main, soft, line, danger;
  _CallArt(this.shot, this.main, this.soft, this.line, this.danger);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final fill = Paint()..color = main;
    final softP = Paint()..color = soft;
    final white = Paint()..color = Colors.white;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = main;
    final whiteStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..color = Colors.white;

    if (shot) {
      // a phone showing a video call ...
      final c0 = Offset(w / 2 - 22, h / 2);
      final phone = RRect.fromRectAndRadius(Rect.fromCenter(center: c0, width: 104, height: 172), const Radius.circular(18));
      canvas.drawRRect(phone, softP);
      canvas.drawRRect(phone, stroke);
      canvas.drawCircle(c0 + const Offset(0, -26), 19, fill);
      final shoulders = Path()
        ..addArc(Rect.fromCenter(center: c0 + const Offset(0, 52), width: 74, height: 84), pi, pi)
        ..close();
      canvas.drawPath(shoulders, fill);
      canvas.drawLine(c0 + const Offset(-14, -76), c0 + const Offset(14, -76), stroke..strokeWidth = 3);
      // ... and a crossed-out camera badge
      final bc = Offset(w / 2 + 54, h / 2 + 46);
      canvas.drawCircle(bc, 34, white);
      canvas.drawCircle(bc, 30, Paint()..color = danger);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: bc, width: 32, height: 22), const Radius.circular(5)), whiteStroke);
      canvas.drawCircle(bc, 5.5, whiteStroke);
      canvas.drawLine(bc + const Offset(-18, -18), bc + const Offset(18, 18), Paint()
        ..color = Colors.white
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round);
    } else {
      // two phones, a dashed line between them and a lock shield in the middle
      final lc = Offset(w * 0.16, h / 2), rc = Offset(w * 0.84, h / 2);
      for (final p in [lc, rc]) {
        final r = RRect.fromRectAndRadius(Rect.fromCenter(center: p, width: 50, height: 90), const Radius.circular(11));
        canvas.drawRRect(r, softP);
        canvas.drawRRect(r, stroke..strokeWidth = 3.5);
        canvas.drawCircle(p + const Offset(0, -10), 9, fill);
        canvas.drawArc(Rect.fromCenter(center: p + const Offset(0, 24), width: 30, height: 34), pi, pi, true, fill);
      }
      final dash = Paint()
        ..color = line
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      for (var x = lc.dx + 34; x < rc.dx - 34; x += 12) {
        canvas.drawLine(Offset(x, h / 2), Offset(x + 6, h / 2), dash);
      }
      final sc = Offset(w / 2, h / 2);
      final shield = Path()
        ..moveTo(sc.dx, sc.dy - 50)
        ..lineTo(sc.dx + 37, sc.dy - 35)
        ..lineTo(sc.dx + 37, sc.dy + 4)
        ..quadraticBezierTo(sc.dx + 37, sc.dy + 36, sc.dx, sc.dy + 54)
        ..quadraticBezierTo(sc.dx - 37, sc.dy + 36, sc.dx - 37, sc.dy + 4)
        ..lineTo(sc.dx - 37, sc.dy - 35)
        ..close();
      canvas.drawPath(shield, Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeJoin = StrokeJoin.round);
      canvas.drawPath(shield, fill);
      canvas.drawArc(Rect.fromCenter(center: sc + const Offset(0, -6), width: 18, height: 22), pi, pi, false, whiteStroke);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: sc + const Offset(0, 7), width: 28, height: 22), const Radius.circular(5)), white);
      canvas.drawCircle(sc + const Offset(0, 7), 3.2, fill);
    }
  }

  @override
  bool shouldRepaint(covariant _CallArt o) => o.shot != shot || o.main != main || o.soft != soft || o.danger != danger;
}
