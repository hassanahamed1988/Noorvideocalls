import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as sio;

late SharedPreferences prefs;
String get base => prefs.getString('server') ?? 'http://127.0.0.1:3000';
String? get tok => prefs.getString('token');
Map<String, String> get hdr => {'Content-Type': 'application/json', 'Authorization': 'Bearer ${tok ?? ''}', 'X-Device': prefs.getString('device') ?? ''};
final navKey = GlobalKey<NavigatorState>();

void forceLogout() {
  if (prefs.getString('token') == null) return;
  prefs.remove('token');
  navKey.currentState?.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const Login()), (_) => false);
}
Future<Map> post(String p, Map b) async {
  final r = await http.post(Uri.parse('$base$p'), headers: hdr, body: jsonEncode(b));
  if (r.statusCode == 401 && !p.startsWith('/auth') && !r.body.contains('need2fa')) {
    forceLogout();
    return <String, dynamic>{};
  }
  return jsonDecode(r.body);
}
    jsonDecode((await http.post(Uri.parse('$base$p'), headers: hdr, body: jsonEncode(b))).body);

final themeMode = ValueNotifier<ThemeMode>(ThemeMode.system);
final lang = ValueNotifier<String>('en');

const langNames = {'en': 'English', 'bn': 'বাংলা', 'ar': 'العربية', 'hi': 'हिन्दी'};

const _tr = {
  'en': {'server': 'Server URL', 'phone': 'Mobile number', 'name': 'Your name', 'otp': 'OTP code', 'sendOtp': 'Send OTP', 'verify': 'Verify', 'otpSent': 'OTP sent', 'noConn': 'Cannot connect to server', 'incoming': 'is calling', 'decline': 'Decline', 'answer': 'Answer', 'nobody': 'No contacts yet', 'audio': 'Audio', 'video': 'Video', 'settings': 'Settings', 'theme': 'Theme', 'system': 'System', 'light': 'Light', 'dark': 'Dark', 'language': 'Language', 'chats': 'Chats', 'contacts': 'Contacts', 'calls': 'Calls', 'search': 'Search', 'typeMsg': 'Type a message', 'noChats': 'No chats yet', 'noCalls': 'No calls yet', 'newGroup': 'New group', 'groupName': 'Group name', 'create': 'Create', 'bio': 'Bio', 'save': 'Save', 'block': 'Block', 'report': 'Report', 'logout': 'Log out', 'phoneH': 'Enter mobile number', 'nameH': 'Enter your name', 'otpH': 'Enter 6-digit code', 'addContact': 'Add contact', 'byPhone': 'Mobile', 'byEmail': 'Email', 'byId': 'User ID', 'userId': 'User ID', 'email': 'Email', 'nationality': 'Nationality', 'birth': 'Date of birth', 'profile': 'Profile', 'security': 'Security', 'twoStep': 'Two-step verification (Google Authenticator)', 'enable': 'Enable', 'disable': 'Disable', 'secretKey': 'Secret key', 'code': '6-digit code', 'added': 'Contact added', 'notFound': 'User not found', 'country': 'Select country', 'verifyEmail': 'Verify', 'sendCode': 'Send code', 'verified': 'Verified', 'add': 'Add', 'copy': 'Copy', 'twoStepOn': 'Two-step verification is on', 'scanHint': 'Scan the QR code, or enter the key in Google Authenticator, then type the 6-digit code', 'codeSent': 'Verification code sent', 'wrongCode': 'Wrong code', 'changeNumber': 'Change number', 'changeInfo': 'Your account, chats and contacts move to the new number. The old number becomes invalid in this app.', 'newNumber': 'New mobile number', 'numChanged': 'Invalid number. This user has changed their number.', 'numTaken': 'This number is already registered', 'badPhone': 'Enter a valid number', 'numDone': 'Number changed successfully', 'confirm': 'Confirm', 'manageDevice': 'Manage Device', 'blockedList': 'Blocked List', 'thisDevice': 'This device', 'lastActive': 'Last active', 'logoutDevice': 'Log out', 'logoutOthers': 'Log out all other devices', 'noBlocked': 'No blocked users', 'unblock': 'Unblock', 'activeNow': 'Active now', 'blockedInfo': 'Blocked users cannot message or call you.', 'camera': 'Camera', 'gallery': 'Gallery'},
  'bn': {'server': 'সার্ভার URL', 'phone': 'মোবাইল নম্বর', 'name': 'আপনার নাম', 'otp': 'OTP কোড', 'sendOtp': 'OTP পাঠান', 'verify': 'যাচাই করুন', 'otpSent': 'OTP পাঠানো হয়েছে', 'noConn': 'সার্ভারে সংযোগ হচ্ছে না', 'incoming': 'কল করছে', 'decline': 'কাটুন', 'answer': 'ধরুন', 'nobody': 'এখনো কেউ নেই', 'audio': 'অডিও', 'video': 'ভিডিও', 'settings': 'সেটিংস', 'theme': 'থিম', 'system': 'সিস্টেম', 'light': 'লাইট', 'dark': 'ডার্ক', 'language': 'ভাষা', 'chats': 'চ্যাট', 'contacts': 'কনটাক্ট', 'calls': 'কল', 'search': 'খুঁজুন', 'typeMsg': 'মেসেজ লিখুন', 'noChats': 'এখনো কোনো চ্যাট নেই', 'noCalls': 'এখনো কোনো কল নেই', 'newGroup': 'নতুন গ্রুপ', 'groupName': 'গ্রুপের নাম', 'create': 'তৈরি করুন', 'bio': 'বায়ো', 'save': 'সেভ', 'block': 'ব্লক', 'report': 'রিপোর্ট', 'logout': 'লগআউট', 'phoneH': 'মোবাইল নম্বর লিখুন', 'nameH': 'আপনার নাম লিখুন', 'otpH': '৬ সংখ্যার কোড লিখুন', 'addContact': 'কনটাক্ট যোগ করুন', 'byPhone': 'মোবাইল', 'byEmail': 'ইমেইল', 'byId': 'ইউজার আইডি', 'userId': 'ইউজার আইডি', 'email': 'ইমেইল', 'nationality': 'জাতীয়তা', 'birth': 'জন্ম তারিখ', 'profile': 'প্রোফাইল', 'security': 'সিকিউরিটি', 'twoStep': 'টু-স্টেপ ভেরিফিকেশন (Google Authenticator)', 'enable': 'চালু করুন', 'disable': 'বন্ধ করুন', 'secretKey': 'সিক্রেট কী', 'code': '৬ সংখ্যার কোড', 'added': 'কনটাক্ট যোগ হয়েছে', 'notFound': 'ইউজার পাওয়া যায়নি', 'country': 'দেশ বাছাই করুন', 'verifyEmail': 'যাচাই করুন', 'sendCode': 'কোড পাঠান', 'verified': 'যাচাইকৃত', 'add': 'যোগ করুন', 'copy': 'কপি', 'twoStepOn': 'টু-স্টেপ ভেরিফিকেশন চালু আছে', 'scanHint': 'QR কোড স্ক্যান করুন বা কী Google Authenticator-এ বসান, তারপর ৬ সংখ্যার কোড লিখুন', 'codeSent': 'ভেরিফিকেশন কোড পাঠানো হয়েছে', 'wrongCode': 'কোড ভুল', 'changeNumber': 'নাম্বার পরিবর্তন', 'changeInfo': 'আপনার অ্যাকাউন্ট, চ্যাট ও কনটাক্ট নতুন নাম্বারে চলে যাবে। পুরোনো নাম্বার এই অ্যাপে ইনভ্যালিড হয়ে যাবে।', 'newNumber': 'নতুন মোবাইল নাম্বার', 'numChanged': 'ইনভ্যালিড নাম্বার। ইউজার তার নাম্বার পরিবর্তন করেছে।', 'numTaken': 'এই নাম্বার আগে থেকেই নিবন্ধিত', 'badPhone': 'সঠিক নাম্বার দিন', 'numDone': 'নাম্বার সফলভাবে পরিবর্তন হয়েছে', 'confirm': 'নিশ্চিত করুন', 'manageDevice': 'ডিভাইস ম্যানেজ', 'blockedList': 'ব্লক তালিকা', 'thisDevice': 'এই ডিভাইস', 'lastActive': 'শেষ সক্রিয়', 'logoutDevice': 'লগআউট', 'logoutOthers': 'অন্য সব ডিভাইস লগআউট করুন', 'noBlocked': 'কোনো ব্লক করা ইউজার নেই', 'unblock': 'আনব্লক', 'activeNow': 'এখন সক্রিয়', 'blockedInfo': 'ব্লক করা ইউজার আপনাকে মেসেজ বা কল করতে পারবে না।', 'camera': 'ক্যামেরা', 'gallery': 'গ্যালারি'},
  'ar': {'server': 'عنوان الخادم', 'phone': 'رقم الجوال', 'name': 'اسمك', 'otp': 'رمز التحقق', 'sendOtp': 'إرسال رمز التحقق', 'verify': 'تأكيد', 'otpSent': 'تم إرسال الرمز', 'noConn': 'تعذّر الاتصال بالخادم', 'incoming': 'يتصل بك', 'decline': 'رفض', 'answer': 'رد', 'nobody': 'لا توجد جهات اتصال بعد', 'audio': 'صوت', 'video': 'فيديو', 'settings': 'الإعدادات', 'theme': 'المظهر', 'system': 'النظام', 'light': 'فاتح', 'dark': 'داكن', 'language': 'اللغة', 'chats': 'الدردشات', 'contacts': 'جهات الاتصال', 'calls': 'المكالمات', 'search': 'بحث', 'typeMsg': 'اكتب رسالة', 'noChats': 'لا توجد دردشات بعد', 'noCalls': 'لا توجد مكالمات بعد', 'newGroup': 'مجموعة جديدة', 'groupName': 'اسم المجموعة', 'create': 'إنشاء', 'bio': 'نبذة', 'save': 'حفظ', 'block': 'حظر', 'report': 'إبلاغ', 'logout': 'تسجيل الخروج', 'phoneH': 'أدخل رقم الجوال', 'nameH': 'أدخل اسمك', 'otpH': 'أدخل الرمز المكوّن من 6 أرقام', 'addContact': 'إضافة جهة اتصال', 'byPhone': 'الجوال', 'byEmail': 'البريد', 'byId': 'المعرّف', 'userId': 'معرّف المستخدم', 'email': 'البريد الإلكتروني', 'nationality': 'الجنسية', 'birth': 'تاريخ الميلاد', 'profile': 'الملف الشخصي', 'security': 'الأمان', 'twoStep': 'التحقق بخطوتين (Google Authenticator)', 'enable': 'تفعيل', 'disable': 'إيقاف', 'secretKey': 'المفتاح السري', 'code': 'رمز من 6 أرقام', 'added': 'تمت إضافة جهة الاتصال', 'notFound': 'المستخدم غير موجود', 'country': 'اختر الدولة', 'verifyEmail': 'تأكيد', 'sendCode': 'إرسال الرمز', 'verified': 'تم التحقق', 'add': 'إضافة', 'copy': 'نسخ', 'twoStepOn': 'التحقق بخطوتين مفعّل', 'scanHint': 'امسح رمز QR أو أدخل المفتاح في Google Authenticator ثم اكتب الرمز', 'codeSent': 'تم إرسال رمز التحقق', 'wrongCode': 'الرمز غير صحيح', 'changeNumber': 'تغيير الرقم', 'changeInfo': 'سينتقل حسابك ومحادثاتك وجهات اتصالك إلى الرقم الجديد. سيصبح الرقم القديم غير صالح في هذا التطبيق.', 'newNumber': 'رقم الجوال الجديد', 'numChanged': 'رقم غير صالح. غيّر المستخدم رقمه.', 'numTaken': 'هذا الرقم مسجّل بالفعل', 'badPhone': 'أدخل رقمًا صحيحًا', 'numDone': 'تم تغيير الرقم بنجاح', 'confirm': 'تأكيد', 'manageDevice': 'إدارة الأجهزة', 'blockedList': 'قائمة المحظورين', 'thisDevice': 'هذا الجهاز', 'lastActive': 'آخر نشاط', 'logoutDevice': 'تسجيل الخروج', 'logoutOthers': 'تسجيل الخروج من جميع الأجهزة الأخرى', 'noBlocked': 'لا يوجد مستخدمون محظورون', 'unblock': 'إلغاء الحظر', 'activeNow': 'نشط الآن', 'blockedInfo': 'لا يستطيع المحظورون مراسلتك أو الاتصال بك.', 'camera': 'الكاميرا', 'gallery': 'المعرض'},
  'hi': {'server': 'सर्वर URL', 'phone': 'मोबाइल नंबर', 'name': 'आपका नाम', 'otp': 'OTP कोड', 'sendOtp': 'OTP भेजें', 'verify': 'सत्यापित करें', 'otpSent': 'OTP भेज दिया गया', 'noConn': 'सर्वर से कनेक्ट नहीं हो सका', 'incoming': 'कॉल कर रहा है', 'decline': 'काटें', 'answer': 'उठाएं', 'nobody': 'अभी कोई नहीं', 'audio': 'ऑडियो', 'video': 'वीडियो', 'settings': 'सेटिंग्स', 'theme': 'थीम', 'system': 'सिस्टम', 'light': 'लाइट', 'dark': 'डार्क', 'language': 'भाषा', 'chats': 'चैट', 'contacts': 'संपर्क', 'calls': 'कॉल', 'search': 'खोजें', 'typeMsg': 'संदेश लिखें', 'noChats': 'अभी कोई चैट नहीं', 'noCalls': 'अभी कोई कॉल नहीं', 'newGroup': 'नया ग्रुप', 'groupName': 'ग्रुप का नाम', 'create': 'बनाएं', 'bio': 'बायो', 'save': 'सेव करें', 'block': 'ब्लॉक', 'report': 'रिपोर्ट', 'logout': 'लॉग आउट', 'phoneH': 'मोबाइल नंबर लिखें', 'nameH': 'अपना नाम लिखें', 'otpH': '6 अंकों का कोड लिखें', 'addContact': 'संपर्क जोड़ें', 'byPhone': 'मोबाइल', 'byEmail': 'ईमेल', 'byId': 'यूज़र आईडी', 'userId': 'यूज़र आईडी', 'email': 'ईमेल', 'nationality': 'राष्ट्रीयता', 'birth': 'जन्म तिथि', 'profile': 'प्रोफाइल', 'security': 'सुरक्षा', 'twoStep': 'टू-स्टेप वेरिफिकेशन (Google Authenticator)', 'enable': 'चालू करें', 'disable': 'बंद करें', 'secretKey': 'सीक्रेट की', 'code': '6 अंकों का कोड', 'added': 'संपर्क जोड़ा गया', 'notFound': 'यूज़र नहीं मिला', 'country': 'देश चुनें', 'verifyEmail': 'सत्यापित करें', 'sendCode': 'कोड भेजें', 'verified': 'सत्यापित', 'add': 'जोड़ें', 'copy': 'कॉपी', 'twoStepOn': 'टू-स्टेप वेरिफिकेशन चालू है', 'scanHint': 'QR कोड स्कैन करें या की Google Authenticator में डालें, फिर 6 अंकों का कोड लिखें', 'codeSent': 'वेरिफिकेशन कोड भेजा गया', 'wrongCode': 'कोड गलत है', 'changeNumber': 'नंबर बदलें', 'changeInfo': 'आपका अकाउंट, चैट और संपर्क नए नंबर पर चले जाएंगे। पुराना नंबर इस ऐप में अमान्य हो जाएगा।', 'newNumber': 'नया मोबाइल नंबर', 'numChanged': 'अमान्य नंबर। यूज़र ने अपना नंबर बदल लिया है।', 'numTaken': 'यह नंबर पहले से पंजीकृत है', 'badPhone': 'सही नंबर लिखें', 'numDone': 'नंबर सफलतापूर्वक बदल गया', 'confirm': 'पुष्टि करें', 'manageDevice': 'डिवाइस प्रबंधन', 'blockedList': 'ब्लॉक सूची', 'thisDevice': 'यह डिवाइस', 'lastActive': 'आखिरी सक्रियता', 'logoutDevice': 'लॉग आउट', 'logoutOthers': 'बाकी सभी डिवाइस से लॉग आउट करें', 'noBlocked': 'कोई ब्लॉक यूज़र नहीं', 'unblock': 'अनब्लॉक', 'activeNow': 'अभी सक्रिय', 'blockedInfo': 'ब्लॉक किए गए यूज़र आपको मैसेज या कॉल नहीं कर सकते।', 'camera': 'कैमरा', 'gallery': 'गैलरी'},
};

final msgTick = ValueNotifier<int>(0);
String get me => prefs.getString('phone') ?? '';
Future<dynamic> getj(String p) async {
  final r = await http.get(Uri.parse('$base$p'), headers: hdr);
  if (r.statusCode == 401) {
    forceLogout();
    return <String, dynamic>{};
  }
  return jsonDecode(r.body);
}
String dm(String a, String b) => ([a, b]..sort()).join('_');
void openCall(BuildContext c, Map r, bool video) =>
    Navigator.push(c, MaterialPageRoute(builder: (_) => CallPage(r, video)));
Future<void> startCall(BuildContext c, List to, bool video) async {
  final r = await post('/call/start', {'to': to, 'video': video});
  if (c.mounted) openCall(c, r, video);
}

class LangScope extends InheritedWidget {
  final String l;
  const LangScope(this.l, {super.key, required super.child});
  @override
  bool updateShouldNotify(LangScope o) => o.l != l;
}

String t(BuildContext c, String k) {
  final l = c.dependOnInheritedWidgetOfExactType<LangScope>()?.l ?? 'en';
  return _tr[l]?[k] ?? _tr['en']![k]!;
}

Color colorFor(String s) => Colors.primaries[(s.isEmpty ? 0 : s.runes.first) % Colors.primaries.length].shade600;

class Avatar extends StatelessWidget {
  final String name;
  final double r;
  final String? url;
  const Avatar(this.name, {this.r = 24, this.url, super.key});
  @override
  Widget build(BuildContext c) => (url != null && url!.isNotEmpty)
      ? CircleAvatar(radius: r, backgroundColor: colorFor(name), backgroundImage: NetworkImage('$base$url'))
      : CircleAvatar(
          radius: r,
          backgroundColor: colorFor(name),
          child: Text(name.isEmpty ? '?' : String.fromCharCode(name.runes.first).toUpperCase(),
              style: TextStyle(color: Colors.white, fontSize: r * .8, fontWeight: FontWeight.w600)));
}

Future<ImageSource?> pickSource(BuildContext c) => showModalBottomSheet<ImageSource>(
    context: c,
    showDragHandle: false,
    shape: const RoundedRectangleBorder(),
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      Widget tile(IconData ic, String label, ImageSource src) => Expanded(
          child: InkWell(
              onTap: () => Navigator.pop(ctx, src),
              child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(10)),
                        child: Icon(ic, size: 30, color: cs.onPrimaryContainer)),
                    const SizedBox(height: 8),
                    Text(label),
                  ]))));
      return SafeArea(
          top: false,
          child: IntrinsicHeight(
              child: Row(children: [
            tile(Icons.photo_camera, t(ctx, 'camera'), ImageSource.camera),
            tile(Icons.photo_library, t(ctx, 'gallery'), ImageSource.gallery),
          ])));
    });

Future<String?> pickAndUpload(String kind, ImageSource src) async {
  if (src == ImageSource.camera && !(await Permission.camera.request()).isGranted) return null;
  final x = await ImagePicker().pickImage(source: src, maxWidth: kind == 'cover' ? 1280 : 512, imageQuality: 80);
  if (x == null) return null;
  final r = await post('/me/photo', {'kind': kind, 'data': base64Encode(await x.readAsBytes())});
  return r['url'];
}

class ProfileHeader extends StatelessWidget {
  final String name;
  final String? cover, avatar;
  final VoidCallback? onCover, onAvatar;
  const ProfileHeader(this.name, {this.cover, this.avatar, this.onCover, this.onAvatar, super.key});
  @override
  Widget build(BuildContext c) {
    final cs = Theme.of(c).colorScheme;
    return SizedBox(
        height: 210,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 160,
              child: GestureDetector(
                  onTap: onCover,
                  child: Container(
                      decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [cs.primary, cs.tertiary]),
                          image: (cover == null || cover!.isEmpty)
                              ? null
                              : DecorationImage(image: NetworkImage('$base$cover'), fit: BoxFit.cover)),
                      child: onCover == null
                          ? null
                          : const Align(
                              alignment: Alignment.topRight,
                              child: Padding(
                                  padding: EdgeInsets.all(12),
                                  child: CircleAvatar(
                                      radius: 18, backgroundColor: Colors.black45, child: Icon(Icons.photo_camera, color: Colors.white, size: 18))))))),
          Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Center(
                  child: GestureDetector(
                      onTap: onAvatar,
                      child: Stack(children: [
                        Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(color: cs.surface, shape: BoxShape.circle),
                            child: Avatar(name, r: 48, url: avatar)),
                        if (onAvatar != null)
                          Positioned(
                              right: 0,
                              bottom: 0,
                              child: CircleAvatar(radius: 15, backgroundColor: cs.primary, child: Icon(Icons.photo_camera, size: 16, color: cs.onPrimary))),
                      ])))),
        ]));
  }
}

String hm(dynamic ts) {
  if (ts == null) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(ts);
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

Widget circleBtn(Color col, IconData ic, VoidCallback on, {double size = 64}) => Material(
    color: col,
    shape: const CircleBorder(),
    child: InkWell(
        customBorder: const CircleBorder(),
        onTap: on,
        child: SizedBox(width: size, height: size, child: Icon(ic, color: Colors.white, size: size * .45))));

Widget emptyState(BuildContext c, IconData ic, String msg) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
  Icon(ic, size: 72, color: Theme.of(c).colorScheme.outline),
  const SizedBox(height: 12),
  Text(msg, style: TextStyle(color: Theme.of(c).colorScheme.outline)),
]));

class WaTransition extends PageTransitionsBuilder {
  const WaTransition();
  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> a, Animation<double> sa, Widget child) {
    final cur = CurvedAnimation(parent: a, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    final sec = CurvedAnimation(parent: sa, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    return SlideTransition(
        position: Tween(begin: Offset.zero, end: const Offset(-0.25, 0)).animate(sec),
        child: SlideTransition(
            position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(cur),
            child: DecoratedBox(
                decoration: const BoxDecoration(boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 16)]),
                child: child)));
  }
}

ThemeData mk(Brightness b) {
  final cs = ColorScheme.fromSeed(seedColor: const Color(0xFF0F8B6D), brightness: b);
  OutlineInputBorder ob(Color col, double w) =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: col, width: w));
  return ThemeData(
      useMaterial3: true,
      colorScheme: cs,
      pageTransitionsTheme: const PageTransitionsTheme(
          builders: {TargetPlatform.android: WaTransition(), TargetPlatform.iOS: WaTransition()}),
      appBarTheme: const AppBarTheme(centerTitle: false, scrolledUnderElevation: 0),
      inputDecorationTheme: InputDecorationTheme(
          border: ob(cs.primary.withOpacity(.5), 1),
          enabledBorder: ob(cs.primary.withOpacity(.5), 1),
          focusedBorder: ob(cs.primary, 2),
          prefixIconColor: cs.primary),
      filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(minimumSize: const Size(64, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)))));
}

class Country {
  final String iso, name, dial;
  const Country(this.iso, this.name, this.dial);
  String get flag => String.fromCharCodes(iso.codeUnits.map((c) => c + 127397));
}

final countries = '''BD|Bangladesh|880
IN|India|91
PK|Pakistan|92
LK|Sri Lanka|94
NP|Nepal|977
BT|Bhutan|975
MV|Maldives|960
AF|Afghanistan|93
SA|Saudi Arabia|966
AE|United Arab Emirates|971
QA|Qatar|974
KW|Kuwait|965
OM|Oman|968
BH|Bahrain|973
JO|Jordan|962
LB|Lebanon|961
IQ|Iraq|964
IR|Iran|98
TR|Türkiye|90
EG|Egypt|20
MA|Morocco|212
DZ|Algeria|213
TN|Tunisia|216
LY|Libya|218
SD|Sudan|249
NG|Nigeria|234
ZA|South Africa|27
KE|Kenya|254
ET|Ethiopia|251
GH|Ghana|233
MY|Malaysia|60
SG|Singapore|65
ID|Indonesia|62
TH|Thailand|66
VN|Vietnam|84
PH|Philippines|63
CN|China|86
JP|Japan|81
KR|South Korea|82
HK|Hong Kong|852
AU|Australia|61
NZ|New Zealand|64
GB|United Kingdom|44
IE|Ireland|353
FR|France|33
DE|Germany|49
IT|Italy|39
ES|Spain|34
PT|Portugal|351
NL|Netherlands|31
SE|Sweden|46
NO|Norway|47
CH|Switzerland|41
RU|Russia|7
UA|Ukraine|380
US|United States|1
CA|Canada|1
MX|Mexico|52
BR|Brazil|55
AR|Argentina|54'''
    .split('\n')
    .map((l) {
      final p = l.split('|');
      return Country(p[0], p[1], p[2]);
    }).toList();

String fullPhone(Country c, String n) => '+${c.dial}${n.replaceAll(RegExp(r'\D'), '').replaceFirst(RegExp(r'^0+'), '')}';

Future<Country?> pickCountry(BuildContext c) => showModalBottomSheet<Country>(
    context: c,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * .8),
    builder: (_) => const CountrySheet());

class CountrySheet extends StatefulWidget {
  const CountrySheet({super.key});
  @override
  State<CountrySheet> createState() => _CS();
}

class _CS extends State<CountrySheet> {
  String q = '';
  @override
  Widget build(BuildContext c) {
    final list = countries.where((x) => x.name.toLowerCase().contains(q.toLowerCase()) || x.dial.contains(q)).toList();
    return SafeArea(
        child: Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
            child: Column(children: [
              Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                      onChanged: (v) => setState(() => q = v),
                      decoration: InputDecoration(labelText: t(c, 'search'), prefixIcon: const Icon(Icons.search)))),
              Expanded(
                  child: ListView(
                      children: list
                          .map((x) => ListTile(
                              leading: Text(x.flag, style: const TextStyle(fontSize: 28)),
                              title: Text(x.name),
                              trailing: Text('+${x.dial}', style: const TextStyle(fontWeight: FontWeight.w600)),
                              onTap: () => Navigator.pop(c, x)))
                          .toList())),
            ])));
  }
}

class PhoneField extends StatelessWidget {
  final TextEditingController ctl;
  final Country country;
  final ValueChanged<Country> onCountry;
  const PhoneField(this.ctl, this.country, this.onCountry, {super.key});
  @override
  Widget build(BuildContext c) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(children: [
        InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () async {
              final x = await pickCountry(c);
              if (x != null) onCountry(x);
            },
            child: Container(
                height: 56,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(c).colorScheme.primary.withOpacity(.5)), borderRadius: BorderRadius.circular(8)),
                child: Row(children: [
                  Text(country.flag, style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 6),
                  Text('+${country.dial}'),
                  const Icon(Icons.arrow_drop_down),
                ]))),
        const SizedBox(width: 8),
        Expanded(
            child: TextField(
                controller: ctl,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(labelText: t(c, 'phone'), hintText: t(c, 'phoneH'), prefixIcon: const Icon(Icons.phone_android)))),
      ]));
}

Widget field(TextEditingController c, String l, IconData i,
        {TextInputType? type, Widget? suffix, ValueChanged<String>? onChanged, String? hint, bool editing = true, bool readOnly = false, VoidCallback? onTap}) =>
    Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: TextField(
            controller: c,
            keyboardType: type,
            onChanged: onChanged,
            readOnly: readOnly || !editing,
            onTap: onTap,
            decoration: InputDecoration(
                labelText: l,
                hintText: hint,
                prefixIcon: Icon(i),
                suffixIcon: suffix,
                border: editing ? null : InputBorder.none,
                enabledBorder: editing ? null : InputBorder.none,
                focusedBorder: editing ? null : InputBorder.none,
                disabledBorder: editing ? null : InputBorder.none)));

Widget infoRow(IconData ic, String label, String? v) =>
    (v == null || v.isEmpty) ? const SizedBox.shrink() : ListTile(leading: Icon(ic), title: Text(v), subtitle: Text(label));

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  prefs = await SharedPreferences.getInstance();
  try {
    String d = '';
    if (Platform.isAndroid) {
      final i = await DeviceInfoPlugin().androidInfo;
      d = '${i.manufacturer} ${i.model}';
    } else if (Platform.isIOS) {
      d = (await DeviceInfoPlugin().iosInfo).name;
    }
    d = d.replaceAll(RegExp(r'[^\x20-\x7E]'), '').trim();
    if (d.isNotEmpty) await prefs.setString('device', d);
  } catch (_) {}
  themeMode.value = ThemeMode.values.byName(prefs.getString('theme') ?? 'system');
  lang.value = prefs.getString('lang') ?? 'en';
  runApp(ValueListenableBuilder<ThemeMode>(
      valueListenable: themeMode,
      builder: (_, m, __) => ValueListenableBuilder<String>(
          valueListenable: lang,
          builder: (_, l, __) => MaterialApp(
              title: 'Noor Video Calls',
              navigatorKey: navKey,
              themeMode: m,
              locale: Locale(l),
              builder: (ctx, child) => LangScope(l, child: child!),
              supportedLocales: const [Locale('en'), Locale('bn'), Locale('ar'), Locale('hi')],
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate
              ],
              theme: mk(Brightness.light),
              darkTheme: mk(Brightness.dark),
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
  bool sent = false, need2 = false;
  String msg = '';
  Country cc = countries.first;
  final tf = TextEditingController();

  Future<void> go() async {
    try {
      await prefs.setString('server', srv.text.trim());
      final r = await post(sent ? '/auth/verify' : '/auth/request-otp',
          {'phone': fullPhone(cc, ph.text), 'name': nm.text.trim(), 'otp': otp.text.trim(), 'totp': tf.text.trim()});
      if (r['need2fa'] == true) return setState(() { need2 = true; msg = t(context, 'code'); });
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

  Widget f(TextEditingController c, String l, {IconData? icon, TextInputType? type, String? hint}) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
          controller: c,
          keyboardType: type,
          decoration: InputDecoration(labelText: l, hintText: hint, prefixIcon: icon == null ? null : Icon(icon))));

  @override
  Widget build(BuildContext c) {
    final cs = Theme.of(c).colorScheme;
    return Scaffold(
        body: ListView(padding: EdgeInsets.zero, children: [
      Container(
          padding: EdgeInsets.fromLTRB(24, MediaQuery.of(c).padding.top + 48, 24, 40),
          decoration: BoxDecoration(
              gradient: LinearGradient(colors: [cs.primary, cs.tertiary], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(36))),
          child: Column(children: [
            ClipRRect(borderRadius: BorderRadius.circular(22), child: Image.asset('assets/logo.png', width: 96, height: 96)),
            const SizedBox(height: 16),
            const Text('Noor Video Calls', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
          ])),
      Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            PhoneField(ph, cc, (x) => setState(() => cc = x)),
            f(nm, t(c, 'name'), hint: t(c, 'nameH'), icon: Icons.person_outline),
            if (sent) f(otp, t(c, 'otp'), hint: t(c, 'otpH'), icon: Icons.lock_outline, type: TextInputType.number),
            if (need2) f(tf, t(c, 'code'), hint: t(c, 'otpH'), icon: Icons.shield_outlined, type: TextInputType.number),
            if (msg.isNotEmpty)
              Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(msg, style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600))),
            FilledButton(onPressed: go, child: Text(t(c, sent ? 'verify' : 'sendOtp'))),
            const SizedBox(height: 8),
            ExpansionTile(title: Text(t(c, 'server')), shape: const Border(), children: [f(srv, t(c, 'server'))]),
            Wrap(
                spacing: 8,
                children: langNames.entries
                    .map((e) => ChoiceChip(
                        label: Text(e.value),
                        selected: lang.value == e.key,
                        onSelected: (_) {
                          lang.value = e.key;
                          prefs.setString('lang', e.key);
                        }))
                    .toList()),
          ])),
    ]));
  }
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _H();
}

class _H extends State<Home> {
  int tab = 0, prevTab = 0;
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
          barrierDismissible: false,
          builder: (_) => Dialog.fullscreen(
              backgroundColor: const Color(0xFF0B3D33),
              child: SafeArea(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Avatar('${d['from']}', r: 56),
                const SizedBox(height: 20),
                Text('${d['from']}', style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text('${t(context, d['video'] == true ? 'video' : 'audio')} · ${t(context, 'incoming')}',
                    style: const TextStyle(color: Colors.white70, fontSize: 16)),
                const SizedBox(height: 90),
                Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  circleBtn(Colors.red, Icons.call_end, () => Navigator.pop(context), size: 72),
                  circleBtn(Colors.green, d['video'] == true ? Icons.videocam : Icons.call, () async {
                    Navigator.pop(context);
                    final r = await post('/call/join', {'room': d['room']});
                    if (mounted) openCall(context, r, d['video'] == true);
                  }, size: 72),
                ]),
              ]))));
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
        body: ClipRect(
            child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, anim) {
                  final dir = tab >= prevTab ? 1.0 : -1.0;
                  final incoming = child.key == ValueKey(tab);
                  return SlideTransition(position: Tween(begin: Offset(incoming ? dir : -dir, 0), end: Offset.zero).animate(anim), child: child);
                },
                child: KeyedSubtree(key: ValueKey(tab), child: pages[tab]))),
        bottomNavigationBar: NavigationBar(selectedIndex: tab, onDestinationSelected: (i) => setState(() {
              prevTab = tab;
              tab = i;
            }), destinations: [
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
            ? emptyState(c, Icons.chat_bubble_outline, t(c, 'noChats'))
            : ListView(
                children: items
                    .map((i) => ListTile(
                        leading: Avatar('${i['title']}', url: i['avatar']),
                        title: Text('${i['title']}'),
                        subtitle: Text('${i['last'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: Text(hm(i['ts']), style: Theme.of(c).textTheme.bodySmall),
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
        appBar: AppBar(title: Text(t(c, 'contacts')), actions: [
          IconButton(
              onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const AddContact())).then((_) => load()),
              icon: const Icon(Icons.person_add_alt_1))
        ]),
        body: Column(children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                  controller: q,
                  onChanged: (_) => load(),
                  decoration: InputDecoration(hintText: t(c, 'search'), prefixIcon: const Icon(Icons.search)))),
          Expanded(
              child: users.isEmpty
                  ? emptyState(c, Icons.people_outline, t(c, 'addContact'))
                  : ListView(
                      children: users
                          .map((u) => ListTile(
                              leading: GestureDetector(
                                  onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => ProfilePage(u['phone']))),
                                  child: Avatar('${u['name']}', url: u['avatar'])),
                              title: Text('${u['name']}'),
                              subtitle: Text('${u['phone']}'),
                              onTap: () => Navigator.push(
                                  c, MaterialPageRoute(builder: (_) => ChatPage({'chat': dm(me, u['phone']), 'title': u['name'], 'peer': u['phone'], 'avatar': u['avatar']}))),
                              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                IconButton(onPressed: () => startCall(c, [u['phone']], false), icon: const Icon(Icons.call)),
                                IconButton(onPressed: () => startCall(c, [u['phone']], true), icon: const Icon(Icons.videocam)),
                              ])))
                          .toList())),
        ]),
      );
}

class AddContact extends StatefulWidget {
  const AddContact({super.key});
  @override
  State<AddContact> createState() => _AC();
}

class _AC extends State<AddContact> {
  int mode = 0;
  Country cc = countries.first;
  final vc = TextEditingController();
  String msg = '';
  bool ok = false;

  Future<void> add() async {
    try {
      final v = mode == 0 ? fullPhone(cc, vc.text) : vc.text.trim();
      final r = await post('/contacts/add', {'type': ['phone', 'email', 'id'][mode], 'value': v});
      setState(() {
        ok = r['user'] != null;
        msg = ok ? '${t(context, 'added')}: ${r['user']['name']}' : t(context, r['error'] == 'number_changed' ? 'numChanged' : 'notFound');
      });
    } catch (_) {
      setState(() {
        ok = false;
        msg = t(context, 'noConn');
      });
    }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: Text(t(c, 'addContact'))),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          SegmentedButton<int>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: 0, icon: const Icon(Icons.phone_android), label: Text(t(c, 'byPhone'), maxLines: 1, overflow: TextOverflow.ellipsis)),
                ButtonSegment(value: 1, icon: const Icon(Icons.email_outlined), label: Text(t(c, 'byEmail'), maxLines: 1, overflow: TextOverflow.ellipsis)),
                ButtonSegment(value: 2, icon: const Icon(Icons.badge_outlined), label: Text(t(c, 'byId'), maxLines: 1, overflow: TextOverflow.ellipsis)),
              ],
              selected: {mode},
              onSelectionChanged: (x) => setState(() {
                    mode = x.first;
                    msg = '';
                    vc.clear();
                  })),
          const SizedBox(height: 20),
          if (mode == 0)
            PhoneField(vc, cc, (x) => setState(() => cc = x))
          else
            field(vc, t(c, mode == 1 ? 'email' : 'userId'), mode == 1 ? Icons.email_outlined : Icons.badge_outlined,
                type: mode == 1 ? TextInputType.emailAddress : TextInputType.text),
          FilledButton.icon(onPressed: add, icon: const Icon(Icons.person_add), label: Text(t(c, 'add'))),
          if (msg.isNotEmpty)
            Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(msg, style: TextStyle(color: ok ? Colors.green : Theme.of(c).colorScheme.error, fontWeight: FontWeight.w600))),
        ]),
      );
}

class ProfilePage extends StatefulWidget {
  final String phone;
  const ProfilePage(this.phone, {super.key});
  @override
  State<ProfilePage> createState() => _PP();
}

class _PP extends State<ProfilePage> {
  Map u = {};
  @override
  void initState() {
    super.initState();
    getj('/profile?phone=${Uri.encodeQueryComponent(widget.phone)}').then((r) => mounted ? setState(() => u = r) : null).catchError((_) {});
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: Text(t(c, 'profile'))),
        body: ListView(padding: const EdgeInsets.only(bottom: 16), children: [
          ProfileHeader('${u['name'] ?? ''}', cover: u['cover'], avatar: u['avatar']),
          const SizedBox(height: 12),
          Center(child: Text('${u['name'] ?? ''}', style: Theme.of(c).textTheme.headlineSmall)),
          if ((u['bio'] ?? '').toString().isNotEmpty) Center(child: Text('${u['bio']}')),
          const SizedBox(height: 12),
          infoRow(Icons.flag_outlined, t(c, 'nationality'), u['nationality']),
          infoRow(Icons.cake_outlined, t(c, 'birth'), u['birthdate']),
          infoRow(Icons.phone_android, t(c, 'phone'), u['phone']),
          infoRow(Icons.email_outlined, t(c, 'email'), u['email']),
          infoRow(Icons.badge_outlined, t(c, 'userId'), u['userId']),
        ]),
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
            ? emptyState(c, Icons.call_outlined, t(c, 'noCalls'))
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
        appBar: AppBar(
            title: GestureDetector(
                onTap: widget.chat['peer'] == null ? null : () => Navigator.push(c, MaterialPageRoute(builder: (_) => ProfilePage(widget.chat['peer']))),
                child: Row(children: [
                  Avatar('${widget.chat['title']}', r: 18, url: widget.chat['avatar']),
                  const SizedBox(width: 10),
                  Flexible(child: Text('${widget.chat['title']}', overflow: TextOverflow.ellipsis)),
                ])),
            actions: [
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
                                borderRadius: BorderRadiusDirectional.only(
                                    topStart: const Radius.circular(16),
                                    topEnd: const Radius.circular(16),
                                    bottomStart: Radius.circular(mine ? 16 : 4),
                                    bottomEnd: Radius.circular(mine ? 4 : 16))),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                              Text('${m['text']}'),
                              Text(hm(m['ts']), style: TextStyle(fontSize: 10, color: Theme.of(c).colorScheme.onSurfaceVariant)),
                            ])));
                  })),
          SafeArea(
              child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(children: [
                    Expanded(
                        child: TextField(
                            controller: tc,
                            onSubmitted: (_) => send(),
                            decoration: InputDecoration(hintText: t(c, 'typeMsg')))),
                    const SizedBox(width: 6),
                    IconButton.filled(onPressed: send, icon: const Icon(Icons.send)),
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
  bool mic = true, cam = false, spk = true;
  final t0 = DateTime.now();
  Timer? tm;

  @override
  void initState() {
    super.initState();
    cam = widget.video;
    spk = widget.video;
    room.addListener(() => mounted ? setState(() {}) : null);
    tm = Timer.periodic(const Duration(seconds: 1), (_) => mounted ? setState(() {}) : null);
    start();
  }

  Future<void> start() async {
    await [Permission.camera, Permission.microphone].request();
    await room.connect(widget.r['url'], widget.r['token']);
    await room.localParticipant?.setMicrophoneEnabled(true);
    await room.localParticipant?.setCameraEnabled(cam);
    try {
      await Hardware.instance.setSpeakerphoneOn(spk);
    } catch (_) {}
  }

  @override
  void dispose() {
    tm?.cancel();
    room.disconnect();
    room.dispose();
    super.dispose();
  }

  String get dur {
    final d = DateTime.now().difference(t0);
    return '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  String nameOf(Participant p) => p.name.isEmpty ? p.identity : p.name;

  Widget tile(Participant p, {double radius = 0}) {
    final pubs = p.videoTrackPublications.where((x) => x.track != null && !x.muted);
    return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Container(
            color: const Color(0xFF16302A),
            child: pubs.isNotEmpty
                ? VideoTrackRenderer(pubs.first.track as VideoTrack)
                : Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Avatar(nameOf(p), r: 44),
                    const SizedBox(height: 10),
                    Text(nameOf(p), style: const TextStyle(color: Colors.white, fontSize: 18)),
                  ]))));
  }

  @override
  Widget build(BuildContext c) {
    final local = room.localParticipant;
    final remotes = room.remoteParticipants.values.toList();
    Widget body;
    if (remotes.length == 1) {
      body = Stack(children: [
        Positioned.fill(child: tile(remotes.first)),
        if (local != null) Positioned(top: 100, right: 16, width: 108, height: 150, child: tile(local, radius: 16)),
      ]);
    } else {
      final all = <Participant>[if (local != null) local, ...remotes];
      body = Padding(
          padding: const EdgeInsets.fromLTRB(8, 100, 8, 140),
          child: GridView.count(
              crossAxisCount: all.length <= 1 ? 1 : 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: all.length <= 2 ? 0.8 : 0.75,
              children: all.map((p) => tile(p, radius: 16)).toList()));
    }
    Widget btn(bool on, IconData onIc, IconData offIc, VoidCallback f) =>
        circleBtn(on ? Colors.white24 : Colors.red.shade400, on ? onIc : offIc, f, size: 56);
    return Scaffold(
        backgroundColor: const Color(0xFF0B1F1A),
        body: Stack(children: [
          Positioned.fill(child: body),
          Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                  child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(children: [
                        IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 30)),
                        Expanded(
                            child: Column(children: [
                          Text(remotes.isEmpty ? '...' : remotes.map(nameOf).join(', '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
                          Text(dur, style: const TextStyle(color: Colors.white70)),
                        ])),
                        const SizedBox(width: 48),
                      ])))),
          Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                  child: Container(
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(36)),
                      child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                        btn(mic, Icons.mic, Icons.mic_off, () async {
                          mic = !mic;
                          await room.localParticipant?.setMicrophoneEnabled(mic);
                          setState(() {});
                        }),
                        btn(cam, Icons.videocam, Icons.videocam_off, () async {
                          cam = !cam;
                          await room.localParticipant?.setCameraEnabled(cam);
                          setState(() {});
                        }),
                        btn(spk, Icons.volume_up, Icons.volume_down, () async {
                          spk = !spk;
                          try {
                            await Hardware.instance.setSpeakerphoneOn(spk);
                          } catch (_) {}
                          setState(() {});
                        }),
                        circleBtn(Colors.red, Icons.call_end, () => Navigator.pop(context), size: 64),
                      ])))),
        ]));
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _S();
}

class _S extends State<SettingsPage> {
  Map me0 = {};
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = await getj('/me');
      if (mounted) setState(() => me0 = r);
    } catch (_) {}
  }

  void edit() => Navigator.push(context, MaterialPageRoute(builder: (_) => const EditProfile())).then((_) => load());

  Future<void> logout() async {
    await prefs.remove('token');
    if (mounted) Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const Login()), (_) => false);
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: Text(t(c, 'settings'))),
        body: ListView(children: [
          ProfileHeader('${me0['name'] ?? ''}', cover: me0['cover'], avatar: me0['avatar'], onCover: edit, onAvatar: edit),
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(children: [
                Text('${me0['name'] ?? ''}', style: Theme.of(c).textTheme.titleLarge),
                Text(me),
                GestureDetector(
                    onTap: () => Clipboard.setData(ClipboardData(text: '${me0['userId'] ?? ''}')),
                    child: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.badge_outlined, size: 16),
                          const SizedBox(width: 4),
                          Text('ID: ${me0['userId'] ?? ''}'),
                          const SizedBox(width: 6),
                          const Icon(Icons.copy, size: 14),
                        ]))),
              ])),
          ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(t(c, 'profile')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const EditProfile())).then((_) => load())),
          ListTile(
              leading: const Icon(Icons.shield_outlined),
              title: Text(t(c, 'security')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const SecurityPage()))),
          ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: Text(t(c, 'changeNumber')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const ChangeNumberPage()))),
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
          const Divider(),
          ListTile(leading: const Icon(Icons.logout), title: Text(t(c, 'logout')), onTap: logout),
        ]),
      );
}

class EditProfile extends StatefulWidget {
  const EditProfile({super.key});
  @override
  State<EditProfile> createState() => _EP();
}

class _EP extends State<EditProfile> {
  final nameC = TextEditingController(), bioC = TextEditingController(), idC = TextEditingController();
  final emailC = TextEditingController(), codeC = TextEditingController();
  final natC = TextEditingController(), birthC = TextEditingController(), phC = TextEditingController(text: me);
  String msg = '';
  String? avatar, cover;
  bool verified = false, codeSent = false, editing = false;

  @override
  void initState() {
    super.initState();
    getj('/me').then((r) {
      nameC.text = r['name'] ?? '';
      bioC.text = r['bio'] ?? '';
      idC.text = r['userId'] ?? '';
      emailC.text = r['email'] ?? '';
      natC.text = r['nationality'] ?? '';
      birthC.text = r['birthdate'] ?? '';
      if (mounted) {
        setState(() {
          verified = r['emailVerified'] == true;
          avatar = r['avatar'];
          cover = r['cover'];
        });
      }
    }).catchError((_) {});
  }

  Future<void> upload(String kind) async {
    try {
      final src = await pickSource(context);
      if (src == null) return;
      final u = await pickAndUpload(kind, src);
      if (u != null && mounted) {
        setState(() {
          if (kind == 'cover') {
            cover = u;
          } else {
            avatar = u;
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => msg = t(context, 'noConn'));
    }
  }

  Future<void> save() async {
    final r = await post('/me', {'name': nameC.text, 'bio': bioC.text, 'nationality': natC.text, 'birthdate': birthC.text, 'userId': idC.text.trim()});
    if (r['error'] != null) return setState(() => msg = '${r['error']}');
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    setState(() {
      editing = false;
      codeSent = false;
      msg = '';
    });
  }

  Future<void> sendCode() async {
    final r = await post('/email/request', {'email': emailC.text.trim()});
    setState(() {
      if (r['error'] != null) {
        msg = '${r['error']}';
      } else {
        codeSent = true;
        msg = r['devCode'] != null ? 'Code: ${r['devCode']}' : t(context, 'codeSent');
      }
    });
  }

  Future<void> verifyCode() async {
    final r = await post('/email/verify', {'code': codeC.text.trim()});
    setState(() {
      if (r['ok'] == true) {
        verified = true;
        codeSent = false;
        msg = t(context, 'verified');
      } else {
        msg = t(context, 'wrongCode');
      }
    });
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: Text(t(c, 'profile')), actions: [
          AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: editing
                  ? TextButton(key: const ValueKey('save'), onPressed: save, child: Text(t(c, 'save')))
                  : IconButton(key: const ValueKey('edit'), onPressed: () => setState(() => editing = true), icon: const Icon(Icons.edit_outlined)))
        ]),
        body: ListView(padding: const EdgeInsets.only(bottom: 16), children: [
          ProfileHeader(nameC.text, cover: cover, avatar: avatar, onCover: () => upload('cover'), onAvatar: () => upload('avatar')),
          const SizedBox(height: 20),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                field(nameC, t(c, 'name'), Icons.person_outline, hint: t(c, 'nameH'), editing: editing),
                field(bioC, t(c, 'bio'), Icons.info_outline, editing: editing),
                field(natC, t(c, 'nationality'), Icons.flag_outlined,
                    editing: editing,
                    readOnly: true,
                    suffix: editing ? const Icon(Icons.arrow_drop_down) : null,
                    onTap: editing
                        ? () async {
                            final x = await pickCountry(c);
                            if (x != null) setState(() => natC.text = x.name);
                          }
                        : null),
                field(birthC, t(c, 'birth'), Icons.cake_outlined,
                    editing: editing,
                    readOnly: true,
                    suffix: editing ? const Icon(Icons.calendar_today_outlined, size: 20) : null,
                    onTap: editing
                        ? () async {
                            final d = await showDatePicker(
                                context: c,
                                initialDate: DateTime.tryParse(birthC.text) ?? DateTime(2000),
                                firstDate: DateTime(1900),
                                lastDate: DateTime.now());
                            if (d != null) setState(() => birthC.text = d.toIso8601String().substring(0, 10));
                          }
                        : null),
                field(phC, t(c, 'phone'), Icons.phone_android, editing: editing, readOnly: true),
                field(idC, t(c, 'userId'), Icons.badge_outlined, editing: editing),
                field(emailC, t(c, 'email'), Icons.email_outlined,
                    type: TextInputType.emailAddress,
                    editing: editing,
                    onChanged: (_) => setState(() => verified = false),
                    suffix: verified
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : (editing ? TextButton(onPressed: sendCode, child: Text(t(c, 'sendCode'))) : null)),
                if (codeSent && editing)
                  Row(children: [
                    Expanded(child: field(codeC, t(c, 'code'), Icons.pin_outlined, type: TextInputType.number)),
                    const SizedBox(width: 8),
                    Padding(padding: const EdgeInsets.only(bottom: 14), child: FilledButton(onPressed: verifyCode, child: Text(t(c, 'verifyEmail')))),
                  ]),
                if (msg.isNotEmpty) Text(msg, style: TextStyle(color: Theme.of(c).colorScheme.primary, fontWeight: FontWeight.w600)),
              ])),
        ]),
      );
}

class SecurityPage extends StatefulWidget {
  const SecurityPage({super.key});
  @override
  State<SecurityPage> createState() => _SP();
}

class _SP extends State<SecurityPage> {
  bool on = false;
  String? secret, uri;
  final cc = TextEditingController();
  String msg = '';

  @override
  void initState() {
    super.initState();
    getj('/me').then((r) => mounted ? setState(() => on = r['totpEnabled'] == true) : null).catchError((_) {});
  }

  Future<void> setup() async {
    final r = await post('/security/totp/setup', {});
    setState(() {
      secret = r['secret'];
      uri = r['uri'];
      msg = r['error'] != null ? '${r['error']}' : '';
    });
  }

  Future<void> act(bool enable) async {
    final r = await post(enable ? '/security/totp/enable' : '/security/totp/disable', {'code': cc.text.trim()});
    setState(() {
      if (r['ok'] == true) {
        on = enable;
        secret = null;
        cc.clear();
        msg = '';
      } else {
        msg = t(context, 'wrongCode');
      }
    });
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: Text(t(c, 'security'))),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.devices_other),
              title: Text(t(c, 'manageDevice')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const ManageDevices()))),
          ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.block),
              title: Text(t(c, 'blockedList')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const BlockedList()))),
          const Divider(),
          ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(on ? Icons.verified_user : Icons.shield_outlined, color: on ? Colors.green : null),
              title: Text(t(c, 'twoStep')),
              subtitle: on ? Text(t(c, 'twoStepOn')) : null),
          const SizedBox(height: 8),
          if (!on && secret == null) FilledButton(onPressed: setup, child: Text(t(c, 'enable'))),
          if (!on && secret != null) ...[
            Text(t(c, 'scanHint')),
            const SizedBox(height: 16),
            Center(child: QrImageView(data: uri!, size: 200, backgroundColor: Colors.white)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: SelectableText(secret!, style: const TextStyle(fontFamily: 'monospace', fontSize: 15))),
              IconButton(onPressed: () => Clipboard.setData(ClipboardData(text: secret!)), icon: const Icon(Icons.copy), tooltip: t(c, 'copy')),
            ]),
            const SizedBox(height: 12),
            field(cc, t(c, 'code'), Icons.pin_outlined, type: TextInputType.number),
            FilledButton(onPressed: () => act(true), child: Text(t(c, 'enable'))),
          ],
          if (on) ...[
            field(cc, t(c, 'code'), Icons.pin_outlined, type: TextInputType.number),
            FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error),
                onPressed: () => act(false),
                child: Text(t(c, 'disable'))),
          ],
          if (msg.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(msg, style: TextStyle(color: Theme.of(c).colorScheme.error))),
        ]),
      );
}

class ChangeNumberPage extends StatefulWidget {
  const ChangeNumberPage({super.key});
  @override
  State<ChangeNumberPage> createState() => _CN();
}

class _CN extends State<ChangeNumberPage> {
  Country cc = countries.first;
  final ph = TextEditingController(), otp = TextEditingController(), tf = TextEditingController();
  bool sent = false, need2 = false;
  String msg = '';

  String err(dynamic e) {
    const m = {'bad_phone': 'badPhone', 'number_taken': 'numTaken', 'wrong_code': 'wrongCode'};
    return m[e] != null ? t(context, m[e]!) : '$e';
  }

  Future<void> send() async {
    try {
      final r = await post('/me/phone/request', {'phone': fullPhone(cc, ph.text)});
      setState(() {
        if (r['error'] != null) {
          msg = err(r['error']);
        } else {
          sent = true;
          msg = r['devOtp'] != null ? 'OTP: ${r['devOtp']}' : t(context, 'otpSent');
        }
      });
    } catch (_) {
      setState(() => msg = t(context, 'noConn'));
    }
  }

  Future<void> confirm() async {
    try {
      final r = await post('/me/phone/confirm', {'otp': otp.text.trim(), 'totp': tf.text.trim()});
      if (r['need2fa'] == true) {
        return setState(() {
          need2 = true;
          msg = t(context, 'code');
        });
      }
      if (r['error'] != null) return setState(() => msg = err(r['error']));
      await prefs.setString('token', r['token']);
      await prefs.setString('phone', r['user']['phone']);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(context, 'numDone'))));
      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const Home()), (_) => false);
    } catch (_) {
      setState(() => msg = t(context, 'noConn'));
    }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: Text(t(c, 'changeNumber'))),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.info_outline),
            const SizedBox(width: 10),
            Expanded(child: Text(t(c, 'changeInfo'))),
          ]),
          const SizedBox(height: 20),
          Text(t(c, 'newNumber'), style: Theme.of(c).textTheme.titleSmall),
          const SizedBox(height: 8),
          PhoneField(ph, cc, (x) => setState(() => cc = x)),
          if (!sent) FilledButton(onPressed: send, child: Text(t(c, 'sendCode'))),
          if (sent) ...[
            field(otp, t(c, 'otp'), Icons.lock_outline, type: TextInputType.number, hint: t(c, 'otpH')),
            if (need2) field(tf, t(c, 'code'), Icons.shield_outlined, type: TextInputType.number, hint: t(c, 'otpH')),
            FilledButton(onPressed: confirm, child: Text(t(c, 'confirm'))),
          ],
          if (msg.isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 14), child: Text(msg, style: TextStyle(color: Theme.of(c).colorScheme.primary, fontWeight: FontWeight.w600))),
        ]),
      );
}

class ManageDevices extends StatefulWidget {
  const ManageDevices({super.key});
  @override
  State<ManageDevices> createState() => _MD();
}

class _MD extends State<ManageDevices> {
  List items = [];
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = await getj('/sessions');
      if (mounted && r is List) setState(() => items = r);
    } catch (_) {}
  }

  Future<void> revoke(String id) async {
    await post('/sessions/revoke', {'id': id});
    load();
  }

  Future<void> revokeOthers() async {
    await post('/sessions/revoke-others', {});
    load();
  }

  String when(BuildContext c, int ms) => DateTime.now().millisecondsSinceEpoch - ms < 120000
      ? t(c, 'activeNow')
      : DateTime.fromMillisecondsSinceEpoch(ms).toString().substring(0, 16);

  @override
  Widget build(BuildContext c) {
    final others = items.where((i) => i['current'] != true).length;
    return Scaffold(
        appBar: AppBar(title: Text(t(c, 'manageDevice'))),
        body: ListView(children: [
          ...items.map((i) => ListTile(
              leading: CircleAvatar(
                  backgroundColor: i['current'] == true ? Theme.of(c).colorScheme.primaryContainer : null,
                  child: const Icon(Icons.smartphone)),
              title: Text('${i['device']}${i['current'] == true ? ' · ${t(c, 'thisDevice')}' : ''}'),
              subtitle: Text('${t(c, 'lastActive')}: ${when(c, i['last'] ?? 0)}'),
              trailing: i['current'] == true ? null : TextButton(onPressed: () => revoke(i['id']), child: Text(t(c, 'logoutDevice'))))),
          if (others > 0)
            Padding(
                padding: const EdgeInsets.all(16),
                child: OutlinedButton.icon(onPressed: revokeOthers, icon: const Icon(Icons.logout), label: Text(t(c, 'logoutOthers')))),
        ]));
  }
}

class BlockedList extends StatefulWidget {
  const BlockedList({super.key});
  @override
  State<BlockedList> createState() => _BL();
}

class _BL extends State<BlockedList> {
  List items = [];
  bool loaded = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = await getj('/blocked');
      if (mounted && r is List) {
        setState(() {
          items = r;
          loaded = true;
        });
      }
    } catch (_) {}
  }

  Future<void> unblock(String phone) async {
    await post('/block', {'phone': phone, 'on': false});
    load();
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: Text(t(c, 'blockedList'))),
        body: Column(children: [
          Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                const Icon(Icons.info_outline, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text(t(c, 'blockedInfo'), style: Theme.of(c).textTheme.bodySmall)),
              ])),
          Expanded(
              child: (loaded && items.isEmpty)
                  ? emptyState(c, Icons.block, t(c, 'noBlocked'))
                  : ListView(
                      children: items
                          .map((u) => ListTile(
                              leading: Avatar('${u['name']}', url: u['avatar']),
                              title: Text('${u['name']}'),
                              subtitle: Text('${u['phone']}'),
                              trailing: OutlinedButton(onPressed: () => unblock(u['phone']), child: Text(t(c, 'unblock')))))
                          .toList())),
        ]),
      );
}
