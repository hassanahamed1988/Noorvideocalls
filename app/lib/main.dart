import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as sio;

late SharedPreferences prefs;
String get base => prefs.getString('server') ?? 'http://127.0.0.1:3000';
String? get tok => prefs.getString('token');
Map<String, String> get hdr => {'Content-Type': 'application/json', 'Authorization': 'Bearer ${tok ?? ''}'};
Future<Map> post(String p, Map b) async =>
    jsonDecode((await http.post(Uri.parse('$base$p'), headers: hdr, body: jsonEncode(b))).body);

final themeMode = ValueNotifier<ThemeMode>(ThemeMode.system);
final lang = ValueNotifier<String>('bn');

const langNames = {'en': 'English', 'bn': 'বাংলা', 'ar': 'العربية', 'hi': 'हिन्दी'};

const _tr = {
  'en': {'server': 'Server URL', 'phone': 'Mobile number (+8801...)', 'name': 'Your name', 'otp': 'OTP code', 'sendOtp': 'Send OTP', 'verify': 'Verify', 'otpSent': 'OTP sent', 'noConn': 'Cannot connect to server', 'incoming': 'is calling', 'decline': 'Decline', 'answer': 'Answer', 'nobody': 'No contacts yet', 'audio': 'Audio', 'video': 'Video', 'settings': 'Settings', 'theme': 'Theme', 'system': 'System', 'light': 'Light', 'dark': 'Dark', 'language': 'Language', 'chats': 'Chats', 'contacts': 'Contacts', 'calls': 'Calls', 'search': 'Search', 'typeMsg': 'Type a message', 'noChats': 'No chats yet', 'noCalls': 'No calls yet', 'newGroup': 'New group', 'groupName': 'Group name', 'create': 'Create', 'bio': 'Bio', 'save': 'Save', 'block': 'Block', 'report': 'Report', 'logout': 'Log out'},
  'bn': {'server': 'সার্ভার URL', 'phone': 'মোবাইল নম্বর (+8801...)', 'name': 'আপনার নাম', 'otp': 'OTP কোড', 'sendOtp': 'OTP পাঠান', 'verify': 'যাচাই করুন', 'otpSent': 'OTP পাঠানো হয়েছে', 'noConn': 'সার্ভারে সংযোগ হচ্ছে না', 'incoming': 'কল করছে', 'decline': 'কাটুন', 'answer': 'ধরুন', 'nobody': 'এখনো কেউ নেই', 'audio': 'অডিও', 'video': 'ভিডিও', 'settings': 'সেটিংস', 'theme': 'থিম', 'system': 'সিস্টেম', 'light': 'লাইট', 'dark': 'ডার্ক', 'language': 'ভাষা', 'chats': 'চ্যাট', 'contacts': 'কনটাক্ট', 'calls': 'কল', 'search': 'খুঁজুন', 'typeMsg': 'মেসেজ লিখুন', 'noChats': 'এখনো কোনো চ্যাট নেই', 'noCalls': 'এখনো কোনো কল নেই', 'newGroup': 'নতুন গ্রুপ', 'groupName': 'গ্রুপের নাম', 'create': 'তৈরি করুন', 'bio': 'বায়ো', 'save': 'সেভ', 'block': 'ব্লক', 'report': 'রিপোর্ট', 'logout': 'লগআউট'},
  'ar': {'server': 'عنوان الخادم', 'phone': 'رقم الجوال (+8801...)', 'name': 'اسمك', 'otp': 'رمز التحقق', 'sendOtp': 'إرسال رمز التحقق', 'verify': 'تأكيد', 'otpSent': 'تم إرسال الرمز', 'noConn': 'تعذّر الاتصال بالخادم', 'incoming': 'يتصل بك', 'decline': 'رفض', 'answer': 'رد', 'nobody': 'لا توجد جهات اتصال بعد', 'audio': 'صوت', 'video': 'فيديو', 'settings': 'الإعدادات', 'theme': 'المظهر', 'system': 'النظام', 'light': 'فاتح', 'dark': 'داكن', 'language': 'اللغة', 'chats': 'الدردشات', 'contacts': 'جهات الاتصال', 'calls': 'المكالمات', 'search': 'بحث', 'typeMsg': 'اكتب رسالة', 'noChats': 'لا توجد دردشات بعد', 'noCalls': 'لا توجد مكالمات بعد', 'newGroup': 'مجموعة جديدة', 'groupName': 'اسم المجموعة', 'create': 'إنشاء', 'bio': 'نبذة', 'save': 'حفظ', 'block': 'حظر', 'report': 'إبلاغ', 'logout': 'تسجيل الخروج'},
  'hi': {'server': 'सर्वर URL', 'phone': 'मोबाइल नंबर (+8801...)', 'name': 'आपका नाम', 'otp': 'OTP कोड', 'sendOtp': 'OTP भेजें', 'verify': 'सत्यापित करें', 'otpSent': 'OTP भेज दिया गया', 'noConn': 'सर्वर से कनेक्ट नहीं हो सका', 'incoming': 'कॉल कर रहा है', 'decline': 'काटें', 'answer': 'उठाएं', 'nobody': 'अभी कोई नहीं', 'audio': 'ऑडियो', 'video': 'वीडियो', 'settings': 'सेटिंग्स', 'theme': 'थीम', 'system': 'सिस्टम', 'light': 'लाइट', 'dark': 'डार्क', 'language': 'भाषा', 'chats': 'चैट', 'contacts': 'संपर्क', 'calls': 'कॉल', 'search': 'खोजें', 'typeMsg': 'संदेश लिखें', 'noChats': 'अभी कोई चैट नहीं', 'noCalls': 'अभी कोई कॉल नहीं', 'newGroup': 'नया ग्रुप', 'groupName': 'ग्रुप का नाम', 'create': 'बनाएं', 'bio': 'बायो', 'save': 'सेव करें', 'block': 'ब्लॉक', 'report': 'रिपोर्ट', 'logout': 'लॉग आउट'},
};

final msgTick = ValueNotifier<int>(0);
String get me => prefs.getString('phone') ?? '';
Future<dynamic> getj(String p) async => jsonDecode((await http.get(Uri.parse('$base$p'), headers: hdr)).body);
String dm(String a, String b) => ([a, b]..sort()).join('_');
void openCall(BuildContext c, Map r, bool video) =>
    Navigator.push(c, MaterialPageRoute(builder: (_) => CallPage(r, video)));
Future<void> startCall(BuildContext c, List to, bool video) async {
  final r = await post('/call/start', {'to': to, 'video': video});
  if (c.mounted) openCall(c, r, video);
}

String t(BuildContext c, String k) => _tr[Localizations.localeOf(c).languageCode]?[k] ?? _tr['en']![k]!;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  prefs = await SharedPreferences.getInstance();
  themeMode.value = ThemeMode.values.byName(prefs.getString('theme') ?? 'system');
  lang.value = prefs.getString('lang') ?? 'bn';
  runApp(ValueListenableBuilder<ThemeMode>(
      valueListenable: themeMode,
      builder: (_, m, __) => ValueListenableBuilder<String>(
          valueListenable: lang,
          builder: (_, l, __) => MaterialApp(
              title: 'Noor Video Calls',
              themeMode: m,
              locale: Locale(l),
              supportedLocales: const [Locale('en'), Locale('bn'), Locale('ar'), Locale('hi')],
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate
              ],
              theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
              darkTheme: ThemeData(colorSchemeSeed: Colors.teal, brightness: Brightness.dark, useMaterial3: true),
              home: tok == null ? const Login() : const Home()))));
}

class Login extends StatefulWidget {
  const Login({super.key});
  @override
  State<Login> createState() => _L();
}

class _L extends State<Login> {
  final srv = TextEditingController(text: 'http://127.0.0.1:3000');
  final ph = TextEditingController(), nm = TextEditingController(), otp = TextEditingController();
  bool sent = false;
  String msg = '';

  Future<void> go() async {
    try {
      await prefs.setString('server', srv.text.trim());
      final r = await post(sent ? '/auth/verify' : '/auth/request-otp',
          {'phone': ph.text.trim(), 'name': nm.text.trim(), 'otp': otp.text.trim()});
      if (r['error'] != null) return setState(() => msg = '${r['error']}');
      if (!sent) {
        return setState(() {
          sent = true;
          msg = r['devOtp'] != null ? 'OTP: ${r['devOtp']}' : t(context, 'otpSent');
        });
      }
      await prefs.setString('token', r['token']);
      await prefs.setString('phone', r['user']['phone']);
      if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const Home()));
    } catch (e) {
      setState(() => msg = t(context, 'noConn'));
    }
  }

  Widget f(TextEditingController c, String l) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(controller: c, decoration: InputDecoration(labelText: l, border: const OutlineInputBorder())));

  @override
  Widget build(BuildContext c) => Scaffold(
      body: SafeArea(
          child: ListView(padding: const EdgeInsets.all(24), children: [
        const SizedBox(height: 40),
        const Text('Noor Video Calls', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
        const SizedBox(height: 24),
        f(srv, t(c, 'server')),
        f(ph, t(c, 'phone')),
        f(nm, t(c, 'name')),
        if (sent) f(otp, t(c, 'otp')),
        Text(msg),
        const SizedBox(height: 12),
        FilledButton(onPressed: go, child: Text(t(c, sent ? 'verify' : 'sendOtp'))),
      ])));
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _H();
}

class _H extends State<Home> {
  int tab = 0;
  late sio.Socket s;

  @override
  void initState() {
    super.initState();
    s = sio.io(base, sio.OptionBuilder().setTransports(['websocket']).setAuth({'token': tok}).build());
    s.on('message', (_) => msgTick.value++);
    s.on('incoming-call', (d) {
      if (!mounted) return;
      showDialog(
          context: context,
          builder: (_) => AlertDialog(title: Text('${d['from']} ${t(context, 'incoming')}'), actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: Text(t(context, 'decline'))),
                FilledButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      final r = await post('/call/join', {'room': d['room']});
                      if (mounted) openCall(context, r, d['video'] == true);
                    },
                    child: Text(t(context, 'answer'))),
              ]));
    });
  }

  @override
  void dispose() {
    s.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final pages = [const ChatsTab(), const ContactsTab(), const CallsTab(), const SettingsPage()];
    return Scaffold(
        body: pages[tab],
        bottomNavigationBar: NavigationBar(selectedIndex: tab, onDestinationSelected: (i) => setState(() => tab = i), destinations: [
          NavigationDestination(icon: const Icon(Icons.chat), label: t(c, 'chats')),
          NavigationDestination(icon: const Icon(Icons.people), label: t(c, 'contacts')),
          NavigationDestination(icon: const Icon(Icons.call), label: t(c, 'calls')),
          NavigationDestination(icon: const Icon(Icons.settings), label: t(c, 'settings')),
        ]));
  }
}

class ChatsTab extends StatefulWidget {
  const ChatsTab({super.key});
  @override
  State<ChatsTab> createState() => _CT();
}

class _CT extends State<ChatsTab> {
  List items = [];
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
      final r = await getj('/chats');
      if (mounted) setState(() => items = r);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: const Text('Noor Video Calls'), actions: [
          IconButton(
              onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const GroupCreate())).then((_) => load()),
              icon: const Icon(Icons.group_add))
        ]),
        body: items.isEmpty
            ? Center(child: Text(t(c, 'noChats')))
            : ListView(
                children: items
                    .map((i) => ListTile(
                        leading: CircleAvatar(child: Text('${i['title']}'.isEmpty ? '?' : '${i['title']}'[0])),
                        title: Text('${i['title']}'),
                        subtitle: Text('${i['last'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => ChatPage(Map.from(i)))).then((_) => load())))
                    .toList()),
      );
}

class ContactsTab extends StatefulWidget {
  const ContactsTab({super.key});
  @override
  State<ContactsTab> createState() => _KT();
}

class _KT extends State<ContactsTab> {
  List users = [];
  final q = TextEditingController();
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = await getj('/users/search?q=${Uri.encodeQueryComponent(q.text.trim())}');
      if (mounted) setState(() => users = r);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(
            title: TextField(
                controller: q,
                onChanged: (_) => load(),
                decoration: InputDecoration(hintText: t(c, 'search'), border: InputBorder.none))),
        body: ListView(
            children: users
                .map((u) => ListTile(
                    leading: CircleAvatar(child: Text('${u['name']}'.isEmpty ? '?' : '${u['name']}'[0])),
                    title: Text('${u['name']}'),
                    subtitle: Text('${u['phone']}'),
                    onTap: () => Navigator.push(
                        c, MaterialPageRoute(builder: (_) => ChatPage({'chat': dm(me, u['phone']), 'title': u['name'], 'peer': u['phone']}))),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(onPressed: () => startCall(c, [u['phone']], false), icon: const Icon(Icons.call)),
                      IconButton(onPressed: () => startCall(c, [u['phone']], true), icon: const Icon(Icons.videocam)),
                    ])))
                .toList()),
      );
}

class CallsTab extends StatefulWidget {
  const CallsTab({super.key});
  @override
  State<CallsTab> createState() => _CaT();
}

class _CaT extends State<CallsTab> {
  List items = [];
  @override
  void initState() {
    super.initState();
    getj('/calls').then((r) => mounted ? setState(() => items = r) : null).catchError((_) {});
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: Text(t(c, 'calls'))),
        body: items.isEmpty
            ? Center(child: Text(t(c, 'noCalls')))
            : ListView(
                children: items
                    .map((i) => ListTile(
                        leading: Icon(i['missed'] == true ? Icons.call_missed : (i['dir'] == 'out' ? Icons.call_made : Icons.call_received),
                            color: i['missed'] == true ? Colors.red : null),
                        title: Text('${i['name']}'),
                        subtitle: Text(DateTime.fromMillisecondsSinceEpoch(i['ts']).toString().substring(0, 16)),
                        trailing: Icon(i['video'] == true ? Icons.videocam : Icons.call)))
                    .toList()),
      );
}

class GroupCreate extends StatefulWidget {
  const GroupCreate({super.key});
  @override
  State<GroupCreate> createState() => _GC();
}

class _GC extends State<GroupCreate> {
  List users = [];
  final sel = <String>{};
  final nc = TextEditingController();
  @override
  void initState() {
    super.initState();
    getj('/users/search?q=').then((r) => mounted ? setState(() => users = r) : null).catchError((_) {});
  }

  Future<void> create() async {
    if (nc.text.trim().isEmpty || sel.isEmpty) return;
    await post('/groups', {'name': nc.text.trim(), 'members': sel.toList()});
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: Text(t(c, 'newGroup')), actions: [TextButton(onPressed: create, child: Text(t(c, 'create')))]),
        body: Column(children: [
          Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(controller: nc, decoration: InputDecoration(labelText: t(c, 'groupName'), border: const OutlineInputBorder()))),
          Expanded(
              child: ListView(
                  children: users
                      .map((u) => CheckboxListTile(
                          title: Text('${u['name']}'),
                          subtitle: Text('${u['phone']}'),
                          value: sel.contains(u['phone']),
                          onChanged: (v) => setState(() => v! ? sel.add(u['phone']) : sel.remove(u['phone']))))
                      .toList())),
        ]),
      );
}

class ChatPage extends StatefulWidget {
  final Map chat;
  const ChatPage(this.chat, {super.key});
  @override
  State<ChatPage> createState() => _CP();
}

class _CP extends State<ChatPage> {
  List msgs = [];
  final tc = TextEditingController();
  final sc = ScrollController();
  String get id => widget.chat['chat'];
  List get others =>
      widget.chat['peer'] != null ? [widget.chat['peer']] : (widget.chat['members'] as List).where((m) => m != me).toList();

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
      final r = await getj('/messages?chat=${Uri.encodeQueryComponent(id)}');
      if (!mounted) return;
      setState(() => msgs = r);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (sc.hasClients) sc.jumpTo(sc.position.maxScrollExtent);
      });
    } catch (_) {}
  }

  Future<void> send() async {
    final txt = tc.text.trim();
    if (txt.isEmpty) return;
    tc.clear();
    await post('/messages', {'chat': id, 'text': txt});
    load();
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: Text('${widget.chat['title']}'), actions: [
          IconButton(onPressed: () => startCall(c, others, false), icon: const Icon(Icons.call)),
          IconButton(onPressed: () => startCall(c, others, true), icon: const Icon(Icons.videocam)),
          if (widget.chat['peer'] != null)
            PopupMenuButton<String>(
                onSelected: (v) async {
                  await post(v == 'block' ? '/block' : '/report', {'phone': widget.chat['peer'], 'on': true, 'reason': 'report'});
                  if (v == 'block' && mounted) Navigator.pop(context);
                },
                itemBuilder: (_) => [
                      PopupMenuItem(value: 'block', child: Text(t(c, 'block'))),
                      PopupMenuItem(value: 'report', child: Text(t(c, 'report'))),
                    ]),
        ]),
        body: Column(children: [
          Expanded(
              child: ListView.builder(
                  controller: sc,
                  padding: const EdgeInsets.all(8),
                  itemCount: msgs.length,
                  itemBuilder: (_, i) {
                    final m = msgs[i];
                    final mine = m['from'] == me;
                    return Align(
                        alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
                        child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 2),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            constraints: BoxConstraints(maxWidth: MediaQuery.of(c).size.width * 0.75),
                            decoration: BoxDecoration(
                                color: mine ? Theme.of(c).colorScheme.primaryContainer : Theme.of(c).colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(12)),
                            child: Text('${m['text']}')));
                  })),
          SafeArea(
              child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(children: [
                    Expanded(
                        child: TextField(
                            controller: tc,
                            onSubmitted: (_) => send(),
                            decoration: InputDecoration(hintText: t(c, 'typeMsg'), border: const OutlineInputBorder()))),
                    IconButton(onPressed: send, icon: const Icon(Icons.send)),
                  ]))),
        ]),
      );
}

class CallPage extends StatefulWidget {
  final Map r;
  final bool video;
  const CallPage(this.r, this.video, {super.key});
  @override
  State<CallPage> createState() => _C();
}

class _C extends State<CallPage> {
  final room = Room(
      roomOptions: const RoomOptions(
          adaptiveStream: true,
          dynacast: true,
          defaultCameraCaptureOptions: CameraCaptureOptions(params: VideoParametersPresets.h720_169),
          defaultVideoPublishOptions: VideoPublishOptions(
              simulcast: true, videoEncoding: VideoEncoding(maxBitrate: 2500000, maxFramerate: 30))));
  bool mic = true, cam = false;

  @override
  void initState() {
    super.initState();
    cam = widget.video;
    room.addListener(() => mounted ? setState(() {}) : null);
    start();
  }

  Future<void> start() async {
    await [Permission.camera, Permission.microphone].request();
    await room.connect(widget.r['url'], widget.r['token']);
    await room.localParticipant?.setMicrophoneEnabled(true);
    await room.localParticipant?.setCameraEnabled(cam);
  }

  @override
  void dispose() {
    room.disconnect();
    room.dispose();
    super.dispose();
  }

  Widget tile(Participant p) {
    final pubs = p.videoTrackPublications.where((t) => t.track != null && !t.muted);
    return Container(
        margin: const EdgeInsets.all(2),
        color: Colors.black87,
        child: pubs.isNotEmpty
            ? VideoTrackRenderer(pubs.first.track as VideoTrack)
            : Center(child: Text(p.name.isEmpty ? p.identity : p.name, style: const TextStyle(color: Colors.white, fontSize: 18))));
  }

  @override
  Widget build(BuildContext c) {
    final ps = <Participant>[if (room.localParticipant != null) room.localParticipant!, ...room.remoteParticipants.values];
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
          child: Column(children: [
        Expanded(
            child: GridView.count(
                crossAxisCount: ps.length <= 1 ? 1 : 2,
                childAspectRatio: ps.length <= 2 ? 0.9 : 0.75,
                children: ps.map(tile).toList())),
        Padding(
            padding: const EdgeInsets.all(12),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              IconButton.filledTonal(
                  onPressed: () async {
                    mic = !mic;
                    await room.localParticipant?.setMicrophoneEnabled(mic);
                    setState(() {});
                  },
                  icon: Icon(mic ? Icons.mic : Icons.mic_off)),
              IconButton.filled(
                  style: IconButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.call_end)),
              IconButton.filledTonal(
                  onPressed: () async {
                    cam = !cam;
                    await room.localParticipant?.setCameraEnabled(cam);
                    setState(() {});
                  },
                  icon: Icon(cam ? Icons.videocam : Icons.videocam_off)),
            ])),
      ])),
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _S();
}

class _S extends State<SettingsPage> {
  final nameC = TextEditingController(), bioC = TextEditingController();

  @override
  void initState() {
    super.initState();
    getj('/me').then((r) {
      nameC.text = r['name'] ?? '';
      bioC.text = r['bio'] ?? '';
    }).catchError((_) {});
  }

  Future<void> saveProfile() => post('/me', {'name': nameC.text, 'bio': bioC.text});

  Future<void> logout() async {
    await prefs.remove('token');
    if (mounted) Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const Login()), (_) => false);
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: Text(t(c, 'settings'))),
        body: ListView(children: [
          Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                TextField(controller: nameC, decoration: InputDecoration(labelText: t(c, 'name'), border: const OutlineInputBorder())),
                const SizedBox(height: 8),
                TextField(controller: bioC, decoration: InputDecoration(labelText: t(c, 'bio'), border: const OutlineInputBorder())),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: FilledButton(onPressed: saveProfile, child: Text(t(c, 'save')))),
                  const SizedBox(width: 8),
                  OutlinedButton(onPressed: logout, child: Text(t(c, 'logout'))),
                ]),
              ])),
          const Divider(),
          ListTile(title: Text(t(c, 'theme'), style: const TextStyle(fontWeight: FontWeight.bold))),
          for (final m in ThemeMode.values)
            RadioListTile<ThemeMode>(
                title: Text(t(c, m.name)),
                value: m,
                groupValue: themeMode.value,
                onChanged: (v) {
                  themeMode.value = v!;
                  prefs.setString('theme', v.name);
                  setState(() {});
                }),
          const Divider(),
          ListTile(title: Text(t(c, 'language'), style: const TextStyle(fontWeight: FontWeight.bold))),
          for (final e in langNames.entries)
            RadioListTile<String>(
                title: Text(e.value),
                value: e.key,
                groupValue: lang.value,
                onChanged: (v) {
                  lang.value = v!;
                  prefs.setString('lang', v);
                  setState(() {});
                }),
        ]),
      );
}
