import 'dart:async';
import 'dart:convert';
import 'dart:io' show Directory, File, Platform;
import 'dart:math' show Random, pi;
import 'dart:typed_data';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:record/record.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as sio;
import 'package:video_player/video_player.dart' hide VideoTrack; // livekit_client also exports VideoTrack

late SharedPreferences prefs;
String get base => prefs.getString('server') ?? 'http://127.0.0.1:3000';
String? get tok => prefs.getString('token');
Map<String, String> get hdr => {'Content-Type': 'application/json', 'Authorization': 'Bearer ${tok ?? ''}', 'X-Device': prefs.getString('device') ?? '', 'X-Device-Id': prefs.getString('deviceId') ?? '',
      'X-Device-Model': prefs.getString('devModel') ?? '', 'X-Device-Brand': prefs.getString('devBrand') ?? '',
      'X-Device-Os': prefs.getString('devOs') ?? '', 'X-Device-Platform': prefs.getString('devPlatform') ?? ''};
final navKey = GlobalKey<NavigatorState>();
Map myPriv = {};
sio.Socket? sock;
const secureCh = MethodChannel('noor/secure');
Future<void> setSecure(bool on) async {
  try {
    await secureCh.invokeMethod('set', {'on': on});
  } catch (_) {}
}

Future<T?> showSheet<T>(BuildContext c, String title, Widget Function(BuildContext) body) => showModalBottomSheet<T>(
    context: c,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    elevation: 0,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SafeArea(
              top: false,
              child: Material(
                  color: cs.surfaceContainerLow,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  clipBehavior: Clip.antiAlias,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const SizedBox(height: 10),
                    Container(width: 40, height: 4, decoration: BoxDecoration(color: cs.onSurface.withOpacity(.6), borderRadius: BorderRadius.circular(2))),
                    Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        child: Text(title, style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600))),
                    const Divider(height: 1),
                    Flexible(child: body(ctx)),
                  ]))));
    });

Future<String?> pickOption(BuildContext c, String title, String cur, Map<String, String> opts) => showSheet<String>(
    c,
    title,
    (ctx) => Column(mainAxisSize: MainAxisSize.min, children: [
          ...opts.entries.map((e) => RadioListTile<String>(title: Text(e.value), value: e.key, groupValue: cur, onChanged: (v) => Navigator.pop(ctx, v))),
          const SizedBox(height: 8),
        ]));

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
  try {
    final d = jsonDecode(r.body);
    return d is Map ? d : {'data': d};
  } catch (_) {
    return {'error': 'Server ${r.statusCode} - update and restart the server'};
  }
}

Future<dynamic> getj(String p) async {
  final r = await http.get(Uri.parse('$base$p'), headers: hdr);
  if (r.statusCode == 401) {
    forceLogout();
    return <String, dynamic>{};
  }
  try {
    return jsonDecode(r.body);
  } catch (_) {
    return <String, dynamic>{};
  }
}

/// POST with an explicit short-lived token (registration / face-verification steps).
Future<Map> postT(String p, Map b, String token) async {
  final r = await http.post(Uri.parse('$base$p'), headers: {...hdr, 'Authorization': 'Bearer $token'}, body: jsonEncode(b));
  try {
    final d = jsonDecode(r.body);
    return d is Map ? d : {'data': d};
  } catch (_) {
    return {'error': r.statusCode == 401 ? 'expired' : 'Server ${r.statusCode}'};
  }
}

// Mobile-number rules per country (same table as the server): dial | min | max | allowed start.
const kPhoneRules = [
  '880|10|10|1[3-9]',
  '91|10|10|[6-9]',
  '92|10|10|3',
  '94|9|9|7',
  '977|10|10|9',
  '975|8|8|[17]7',
  '960|7|7|[79]',
  '93|9|9|7',
  '966|9|9|5',
  '971|9|9|5',
  '974|8|8|[3567]',
  '965|8|8|[569]',
  '968|8|8|[79]',
  '973|8|8|3',
  '962|9|9|7',
  '961|7|8|[0-9]',
  '964|10|10|7',
  '98|10|10|9',
  '90|10|10|5',
  '20|10|10|1',
  '212|9|9|[67]',
  '213|9|9|[567]',
  '216|8|8|[2459]',
  '218|9|9|9',
  '249|9|9|[19]',
  '234|10|10|[789]',
  '27|9|9|[678]',
  '254|9|9|[17]',
  '251|9|9|[97]',
  '233|9|9|[25]',
  '60|9|10|1',
  '65|8|8|[89]',
  '62|9|12|8',
  '66|9|9|[689]',
  '84|9|9|[35789]',
  '63|10|10|9',
  '86|11|11|1',
  '81|10|10|[789]0',
  '82|9|10|1',
  '852|8|8|[569]',
  '61|9|9|4',
  '64|8|10|2',
  '44|10|10|7',
  '353|9|9|8',
  '33|9|9|[67]',
  '49|10|11|1[567]',
  '39|9|10|3',
  '34|9|9|[67]',
  '351|9|9|9',
  '31|9|9|6',
  '46|9|9|7',
  '47|8|8|[49]',
  '41|9|9|7',
  '7|10|10|9',
  '380|9|9|[35679]',
  '1|10|10|[2-9]',
  '52|10|10|[1-9]',
  '55|11|11|[1-9]',
  '54|10|11|[1-9]',
];
final phoneRules = () {
  final m = <String, List<dynamic>>{};
  for (final l in kPhoneRules) {
    final p = l.split('|');
    m[p[0]] = [int.parse(p[1]), int.parse(p[2]), RegExp('^${p[3]}')];
  }
  return m;
}();

bool validNational(String dial, String raw) {
  final d = raw.replaceAll(RegExp(r'\D'), '').replaceFirst(RegExp(r'^0+'), '');
  final r = phoneRules[dial];
  if (r == null) return d.length >= 7 && d.length <= 12;
  return d.length >= r[0] && d.length <= r[1] && (r[2] as RegExp).hasMatch(d);
}

String errMsg(BuildContext c, dynamic e) {
  const m = {
    'not_registered': 'notRegistered', 'phone_registered': 'phoneRegistered', 'invalid_number': 'invalidNumber',
    'otp_wrong': 'wrongCode', 'totp_wrong': 'wrongCode', 'expired': 'codeExpired', 'too_fast': 'tooFast',
    'email_taken': 'emailTaken', 'invalid_email': 'badEmail', 'invalid_name': 'fillAll', 'invalid_nat': 'fillAll',
    'invalid_birth': 'fillAll', 'blocked': 'accBlocked', 'face_mismatch': 'faceMismatch', 'locked': 'faceLocked',
    'face_service': 'faceService', 'no_face': 'faceNoFace', 'multiple_faces': 'faceMulti', 'blurry': 'faceBlur',
    'low_quality': 'faceQuality', 'wrong_pose': 'facePose',
  };
  return m[e] != null ? t(c, m[e]!) : '$e';
}

Future<void> finishLogin(BuildContext c, Map r) async {
  await prefs.setString('token', r['token']);
  await prefs.setString('phone', r['user']['phone']);
  if (c.mounted) Navigator.pushAndRemoveUntil(c, MaterialPageRoute(builder: (_) => const Home()), (_) => false);
}

final themeMode = ValueNotifier<ThemeMode>(ThemeMode.system);
final lang = ValueNotifier<String>('en');

const langNames = {'en': 'English', 'bn': 'বাংলা', 'ar': 'العربية', 'hi': 'हिन्दी'};

const _tr = {
  'en': {'server': 'Server URL', 'phone': 'Mobile number', 'name': 'Your name', 'otp': 'OTP code', 'sendOtp': 'Send OTP', 'verify': 'Verify', 'otpSent': 'OTP sent', 'noConn': 'Cannot connect to server', 'incoming': 'is calling', 'decline': 'Decline', 'answer': 'Answer', 'nobody': 'No contacts yet', 'audio': 'Audio', 'video': 'Video', 'settings': 'Settings', 'theme': 'Theme', 'system': 'System', 'light': 'Light', 'dark': 'Dark', 'language': 'Language', 'chats': 'Chats', 'contacts': 'Contacts', 'calls': 'Calls', 'search': 'Search', 'typeMsg': 'Type a message', 'noChats': 'No chats yet', 'noCalls': 'No calls yet', 'newGroup': 'New group', 'groupName': 'Group name', 'create': 'Create', 'bio': 'Bio', 'save': 'Save', 'block': 'Block', 'report': 'Report', 'logout': 'Log out', 'phoneH': 'Enter mobile number', 'nameH': 'Enter your name', 'otpH': 'Enter 6-digit code', 'addContact': 'Add contact', 'byPhone': 'Mobile', 'byEmail': 'Email', 'byId': 'User ID', 'userId': 'User ID', 'email': 'Email', 'nationality': 'Nationality', 'birth': 'Date of birth', 'profile': 'Profile', 'security': 'Security', 'twoStep': 'Two-step verification (Google Authenticator)', 'enable': 'Enable', 'disable': 'Disable', 'secretKey': 'Secret key', 'code': '6-digit code', 'added': 'Contact added', 'notFound': 'User not found', 'country': 'Select country', 'verifyEmail': 'Verify', 'sendCode': 'Send code', 'verified': 'Verified', 'add': 'Add', 'copy': 'Copy', 'twoStepOn': 'Two-step verification is on', 'scanHint': 'Scan the QR code, or enter the key in Google Authenticator, then type the 6-digit code', 'codeSent': 'Verification code sent', 'wrongCode': 'Wrong code', 'changeNumber': 'Change number', 'changeInfo': 'Your account, chats and contacts move to the new number. The old number becomes invalid in this app.', 'newNumber': 'New mobile number', 'numChanged': 'Invalid number. This user has changed their number.', 'numTaken': 'This number is already registered', 'badPhone': 'Enter a valid number', 'numDone': 'Number changed successfully', 'confirm': 'Confirm', 'manageDevice': 'Manage Device', 'blockedList': 'Blocked List', 'thisDevice': 'This device', 'lastActive': 'Last active', 'logoutDevice': 'Log out', 'logoutOthers': 'Log out all other devices', 'noBlocked': 'No blocked users', 'unblock': 'Unblock', 'activeNow': 'Active now', 'blockedInfo': 'Blocked users cannot message or call you.', 'camera': 'Camera', 'gallery': 'Gallery', 'privacy': 'Privacy', 'chatCall': 'Chat & Call Privacy', 'privacyChat': 'Privacy Chat', 'privacyChatInfo': 'Messages disappear after the chosen time and screenshots are blocked in chats', 'timer': 'Disappear after', 'h1': '1 hour', 'h24': '24 hours', 'd7': '7 days', 'shotCalls': 'Block Screenshot For Calls', 'callsHdr': 'Calls', 'whoCall': 'Who can Call Me', 'everyone': 'Everyone', 'contactsOnly': 'My Contacts', 'nobodyOpt': 'Nobody', 'lastSeenOpt': 'Last Seen & Online Status', 'inputStatus': 'Input Status', 'readRec': 'Read receipts', 'profileHdr': 'Profile Privacy', 'shotProfile': 'Block Screenshot for Profile', 'lockProfile': 'Lock Profile', 'whoProfile': 'Who Can See My Profile', 'addingHdr': 'Method for Adding Me', 'addAfter': 'Add me after I accept requests', 'profileShare': 'Profile Share', 'qrCode': 'QR Code', 'copied': 'Copied', 'cantCall': 'This user does not accept calls from you', 'requests': 'Contact requests', 'accept': 'Accept', 'reqSent': 'Request sent. They must accept before you are connected.', 'online': 'Online', 'lastSeenAt': 'Last seen', 'typing': 'typing…', 'locked': 'This profile is private', 'noReq': 'No requests', 'account': 'Account', 'privacySecurity': 'Privacy & Security', 'profilePhoto': 'Profile photo', 'coverPhoto': 'Cover photo', 'personalInfo': 'Personal information', 'contactInfo': 'Contact & account', 'today': 'Today', 'yesterday': 'Yesterday', 'home': 'Home', 'noActive': 'No contacts are active right now', 'story': 'Story', 'myStory': 'My Story', 'addStory': 'Add story', 'textStory': 'Text', 'postStory': 'Post', 'storyText': 'Type your story', 'caption': 'Add a caption', 'replyLbl': 'Reply', 'viewers': 'Viewed by', 'noViewers': 'No views yet', 'deleteStory': 'Delete story', 'whoStory': 'Who can see my Story', 'replySent': 'Reply sent', 'myProfile': 'My Profile', 'media': 'Media', 'autoPhotos': 'Save received photos to gallery', 'autoVideos': 'Save received videos to gallery', 'mediaInfo': 'Photos and videos other users send you are saved to your phone gallery automatically.', 'sendMedia': 'Send media', 'saved': 'Saved to gallery', 'recordVideo': 'Record', 'tooBig': 'File is too large (max 50 MB)', 'holdToRecord': 'Hold to record, release to send', 'slideCancel': 'Slide left to cancel', 'register': 'Register', 'regLink': 'New here? Register', 'loginLink': 'Already have an account? Log in', 'submit': 'Submit', 'verifyTitle': 'Verify your number', 'enterCodeTo': 'Enter the code sent to', 'resend': 'Resend code', 'verifySuccess': 'Verification successful', 'phoneRegistered': 'You have already opened an account with this number. Please log in.', 'notRegistered': 'No account found with this number. Please register first.', 'invalidNumber': 'This number is not valid for the selected country', 'badEmail': 'Enter a valid email address', 'fillAll': 'Please fill in all the fields', 'emailTaken': 'This email is already used by another account', 'codeExpired': 'The code has expired. Request a new one.', 'tooFast': 'Please wait a moment before requesting again', 'accBlocked': 'This account is blocked', 'logIn': 'Log in', 'faceTitle': 'Face verification', 'faceInfo': 'We verify that a real person owns this account. Your face photos are stored on our server to re-check your identity when you log in on a new phone.', 'faceConsent': 'I agree to store my face photos for identity verification', 'faceStep1': 'Step 1: look straight at the camera', 'faceStep2': 'Step 2: turn your head slightly to one side', 'faceDone': 'Both photos accepted', 'openCamera': 'Open camera', 'cont': 'Continue', 'faceNoFace': 'No face found. Make sure your face is clearly visible', 'faceMulti': 'Only one face should be in the photo', 'faceBlur': 'The photo is blurry. Hold still and try again', 'faceQuality': 'Photo quality is low. Use better light', 'facePose': 'Follow the head position shown in the step', 'faceMismatch': 'Your face does not match this account', 'faceLocked': 'Too many attempts. Try again in 15 minutes', 'faceService': 'Face service is unavailable. Try again shortly', 'secShort': 's', 'deviceDetails': 'Device details', 'devDevice': 'Device', 'devName': 'Device name', 'devModel': 'Model', 'devOs': 'System', 'devLocation': 'Location', 'devCountry': 'Country', 'devCity': 'City / region', 'devIsp': 'Internet provider', 'devIp': 'IP address', 'devLocalIp': 'local', 'devNetwork': 'Network', 'devActivity': 'Activity', 'devFirst': 'First login', 'devLastLogin': 'Last login', 'devLoggedOut': 'Logged out', 'devStillIn': 'Still logged in', 'devLastActive': 'Last active', 'devActive': 'Active', 'devUnknown': 'Unknown', 'devLogoutThis': 'Log out this device', 'devViaServer': 'Local network: the location is taken from the internet connection of the server', 'devApprox': 'The location is approximate and based on the IP address', 'msgTimer': 'Message timer', 'timerOff': 'Off', 't1m': '1 month', 't2m': '2 months', 't90': '90 days (maximum)', 'timerDefault': 'Use Privacy setting', 'timerInfo': 'Applies to new messages in all chats. Off: messages are never removed automatically from your account. You can set a different timer for one chat from its menu.', 'timerSaved': 'Message timer updated'},
  'bn': {'server': 'সার্ভার URL', 'phone': 'মোবাইল নম্বর', 'name': 'আপনার নাম', 'otp': 'OTP কোড', 'sendOtp': 'OTP পাঠান', 'verify': 'যাচাই করুন', 'otpSent': 'OTP পাঠানো হয়েছে', 'noConn': 'সার্ভারে সংযোগ হচ্ছে না', 'incoming': 'কল করছে', 'decline': 'কাটুন', 'answer': 'ধরুন', 'nobody': 'এখনো কেউ নেই', 'audio': 'অডিও', 'video': 'ভিডিও', 'settings': 'সেটিংস', 'theme': 'থিম', 'system': 'সিস্টেম', 'light': 'লাইট', 'dark': 'ডার্ক', 'language': 'ভাষা', 'chats': 'চ্যাট', 'contacts': 'কনটাক্ট', 'calls': 'কল', 'search': 'খুঁজুন', 'typeMsg': 'মেসেজ লিখুন', 'noChats': 'এখনো কোনো চ্যাট নেই', 'noCalls': 'এখনো কোনো কল নেই', 'newGroup': 'নতুন গ্রুপ', 'groupName': 'গ্রুপের নাম', 'create': 'তৈরি করুন', 'bio': 'বায়ো', 'save': 'সেভ', 'block': 'ব্লক', 'report': 'রিপোর্ট', 'logout': 'লগআউট', 'phoneH': 'মোবাইল নম্বর লিখুন', 'nameH': 'আপনার নাম লিখুন', 'otpH': '৬ সংখ্যার কোড লিখুন', 'addContact': 'কনটাক্ট যোগ করুন', 'byPhone': 'মোবাইল', 'byEmail': 'ইমেইল', 'byId': 'ইউজার আইডি', 'userId': 'ইউজার আইডি', 'email': 'ইমেইল', 'nationality': 'জাতীয়তা', 'birth': 'জন্ম তারিখ', 'profile': 'প্রোফাইল', 'security': 'সিকিউরিটি', 'twoStep': 'টু-স্টেপ ভেরিফিকেশন (Google Authenticator)', 'enable': 'চালু করুন', 'disable': 'বন্ধ করুন', 'secretKey': 'সিক্রেট কী', 'code': '৬ সংখ্যার কোড', 'added': 'কনটাক্ট যোগ হয়েছে', 'notFound': 'ইউজার পাওয়া যায়নি', 'country': 'দেশ বাছাই করুন', 'verifyEmail': 'যাচাই করুন', 'sendCode': 'কোড পাঠান', 'verified': 'যাচাইকৃত', 'add': 'যোগ করুন', 'copy': 'কপি', 'twoStepOn': 'টু-স্টেপ ভেরিফিকেশন চালু আছে', 'scanHint': 'QR কোড স্ক্যান করুন বা কী Google Authenticator-এ বসান, তারপর ৬ সংখ্যার কোড লিখুন', 'codeSent': 'ভেরিফিকেশন কোড পাঠানো হয়েছে', 'wrongCode': 'কোড ভুল', 'changeNumber': 'নাম্বার পরিবর্তন', 'changeInfo': 'আপনার অ্যাকাউন্ট, চ্যাট ও কনটাক্ট নতুন নাম্বারে চলে যাবে। পুরোনো নাম্বার এই অ্যাপে ইনভ্যালিড হয়ে যাবে।', 'newNumber': 'নতুন মোবাইল নাম্বার', 'numChanged': 'ইনভ্যালিড নাম্বার। ইউজার তার নাম্বার পরিবর্তন করেছে।', 'numTaken': 'এই নাম্বার আগে থেকেই নিবন্ধিত', 'badPhone': 'সঠিক নাম্বার দিন', 'numDone': 'নাম্বার সফলভাবে পরিবর্তন হয়েছে', 'confirm': 'নিশ্চিত করুন', 'manageDevice': 'ডিভাইস ম্যানেজ', 'blockedList': 'ব্লক তালিকা', 'thisDevice': 'এই ডিভাইস', 'lastActive': 'শেষ সক্রিয়', 'logoutDevice': 'লগআউট', 'logoutOthers': 'অন্য সব ডিভাইস লগআউট করুন', 'noBlocked': 'কোনো ব্লক করা ইউজার নেই', 'unblock': 'আনব্লক', 'activeNow': 'এখন সক্রিয়', 'blockedInfo': 'ব্লক করা ইউজার আপনাকে মেসেজ বা কল করতে পারবে না।', 'camera': 'ক্যামেরা', 'gallery': 'গ্যালারি', 'privacy': 'গোপনীয়তা', 'chatCall': 'চ্যাট ও কল প্রাইভেসি', 'privacyChat': 'প্রাইভেসি চ্যাট', 'privacyChatInfo': 'নির্ধারিত সময় পরে মেসেজ মুছে যায় এবং চ্যাটে স্ক্রিনশট বন্ধ থাকে', 'timer': 'মেসেজ মুছবে', 'h1': '১ ঘণ্টা', 'h24': '২৪ ঘণ্টা', 'd7': '৭ দিন', 'shotCalls': 'কলে স্ক্রিনশট ব্লক', 'callsHdr': 'কল', 'whoCall': 'কে আমাকে কল করতে পারবে', 'everyone': 'সবাই', 'contactsOnly': 'আমার কনটাক্ট', 'nobodyOpt': 'কেউ না', 'lastSeenOpt': 'শেষ দেখা ও অনলাইন স্ট্যাটাস', 'inputStatus': 'ইনপুট স্ট্যাটাস', 'readRec': 'রিড রিসিপ্ট', 'profileHdr': 'প্রোফাইল প্রাইভেসি', 'shotProfile': 'প্রোফাইলে স্ক্রিনশট ব্লক', 'lockProfile': 'প্রোফাইল লক', 'whoProfile': 'কে আমার প্রোফাইল দেখতে পারবে', 'addingHdr': 'আমাকে যোগ করার পদ্ধতি', 'addAfter': 'আমি অনুরোধ গ্রহণ করার পর যোগ করা যাবে', 'profileShare': 'প্রোফাইল শেয়ার', 'qrCode': 'QR কোড', 'copied': 'কপি হয়েছে', 'cantCall': 'এই ইউজার আপনার কল নেন না', 'requests': 'কনটাক্ট অনুরোধ', 'accept': 'গ্রহণ', 'reqSent': 'অনুরোধ পাঠানো হয়েছে। সে গ্রহণ করলে সংযুক্ত হবেন।', 'online': 'অনলাইন', 'lastSeenAt': 'শেষ দেখা', 'typing': 'টাইপ করছে…', 'locked': 'এই প্রোফাইল প্রাইভেট', 'noReq': 'কোনো অনুরোধ নেই', 'account': 'অ্যাকাউন্ট', 'privacySecurity': 'প্রাইভেসি ও সিকিউরিটি', 'profilePhoto': 'প্রোফাইল ফটো', 'coverPhoto': 'কাভার ফটো', 'personalInfo': 'ব্যক্তিগত তথ্য', 'contactInfo': 'যোগাযোগ ও অ্যাকাউন্ট', 'today': 'আজ', 'yesterday': 'গতকাল', 'home': 'হোম', 'noActive': 'এখন কেউ সক্রিয় নেই', 'story': 'স্টোরি', 'myStory': 'আমার স্টোরি', 'addStory': 'স্টোরি যোগ করুন', 'textStory': 'লেখা', 'postStory': 'পোস্ট', 'storyText': 'আপনার স্টোরি লিখুন', 'caption': 'ক্যাপশন লিখুন', 'replyLbl': 'উত্তর', 'viewers': 'যারা দেখেছে', 'noViewers': 'এখনো কেউ দেখেনি', 'deleteStory': 'স্টোরি মুছুন', 'whoStory': 'কে আমার স্টোরি দেখতে পারবে', 'replySent': 'উত্তর পাঠানো হয়েছে', 'myProfile': 'আমার প্রোফাইল', 'media': 'মিডিয়া', 'autoPhotos': 'পাওয়া ছবি গ্যালারিতে সেভ করুন', 'autoVideos': 'পাওয়া ভিডিও গ্যালারিতে সেভ করুন', 'mediaInfo': 'অন্য ইউজার ছবি বা ভিডিও পাঠালে নিজে থেকে ফোনের গ্যালারিতে সেভ হবে।', 'sendMedia': 'মিডিয়া পাঠান', 'saved': 'গ্যালারিতে সেভ হয়েছে', 'recordVideo': 'রেকর্ড', 'tooBig': 'ফাইলটি অনেক বড় (সর্বোচ্চ ৫০ MB)', 'holdToRecord': 'ধরে রেখে রেকর্ড করুন, ছাড়লে পাঠানো হবে', 'slideCancel': 'বাতিল করতে বাঁয়ে টানুন', 'register': 'রেজিস্ট্রেশন', 'regLink': 'নতুন? রেজিস্ট্রেশন করুন', 'loginLink': 'আগে থেকেই অ্যাকাউন্ট আছে? লগইন করুন', 'submit': 'সাবমিট', 'verifyTitle': 'নাম্বার যাচাই', 'enterCodeTo': 'যে নাম্বারে কোড গেছে', 'resend': 'আবার কোড পাঠান', 'verifySuccess': 'ভেরিফিকেশন সফল হয়েছে', 'phoneRegistered': 'আপনি এই নাম্বার দিয়ে আগেই অ্যাকাউন্ট খুলেছেন। অনুগ্রহ করে লগইন করুন।', 'notRegistered': 'এই নাম্বারে কোনো অ্যাকাউন্ট নেই। আগে রেজিস্ট্রেশন করুন।', 'invalidNumber': 'নির্বাচিত দেশের জন্য এই নাম্বারটি সঠিক নয়', 'badEmail': 'সঠিক ইমেইল দিন', 'fillAll': 'সব তথ্য পূরণ করুন', 'emailTaken': 'এই ইমেইল অন্য অ্যাকাউন্টে ব্যবহৃত', 'codeExpired': 'কোডের সময় শেষ। নতুন কোড নিন।', 'tooFast': 'আবার চাইতে একটু অপেক্ষা করুন', 'accBlocked': 'এই অ্যাকাউন্ট ব্লকড', 'logIn': 'লগইন', 'faceTitle': 'ফেস ভেরিফিকেশন', 'faceInfo': 'এই অ্যাকাউন্টের মালিক সত্যিই একজন মানুষ কি না আমরা যাচাই করি। নতুন ফোনে লগইন করলে আপনাকে চেনার জন্য আপনার মুখের ছবি আমাদের সার্ভারে রাখা হয়।', 'faceConsent': 'পরিচয় যাচাইয়ের জন্য আমার মুখের ছবি সংরক্ষণে সম্মত', 'faceStep1': 'ধাপ ১: সোজা ক্যামেরার দিকে তাকান', 'faceStep2': 'ধাপ ২: মাথা একটু একদিকে ঘোরান', 'faceDone': 'দুটো ছবিই গৃহীত', 'openCamera': 'ক্যামেরা খুলুন', 'cont': 'চালিয়ে যান', 'faceNoFace': 'মুখ পাওয়া যায়নি। মুখ পরিষ্কার দেখা যায় এমনভাবে তুলুন', 'faceMulti': 'ছবিতে শুধু একজনের মুখ থাকতে হবে', 'faceBlur': 'ছবি ঝাপসা। স্থির থেকে আবার তুলুন', 'faceQuality': 'ছবির মান কম। ভালো আলোতে তুলুন', 'facePose': 'ধাপে বলা মাথার অবস্থান অনুসরণ করুন', 'faceMismatch': 'আপনার মুখ এই অ্যাকাউন্টের সাথে মেলেনি', 'faceLocked': 'অনেকবার চেষ্টা হয়েছে। ১৫ মিনিট পরে আবার চেষ্টা করুন', 'faceService': 'ফেস সার্ভিস এখন পাওয়া যাচ্ছে না। একটু পরে চেষ্টা করুন', 'secShort': 'সে', 'deviceDetails': 'ডিভাইসের বিবরণ', 'devDevice': 'ডিভাইস', 'devName': 'ডিভাইসের নাম', 'devModel': 'মডেল', 'devOs': 'সিস্টেম', 'devLocation': 'লোকেশন', 'devCountry': 'দেশ', 'devCity': 'শহর / অঞ্চল', 'devIsp': 'ইন্টারনেট প্রোভাইডার', 'devIp': 'আইপি নাম্বার', 'devLocalIp': 'লোকাল', 'devNetwork': 'নেটওয়ার্ক', 'devActivity': 'কার্যক্রম', 'devFirst': 'প্রথম লগইন', 'devLastLogin': 'শেষ লগইন', 'devLoggedOut': 'লগআউট করেছে', 'devStillIn': 'এখনো লগইন আছে', 'devLastActive': 'শেষ সক্রিয়', 'devActive': 'সক্রিয়', 'devUnknown': 'অজানা', 'devLogoutThis': 'এই ডিভাইস লগআউট করুন', 'devViaServer': 'লোকাল নেটওয়ার্ক: সার্ভারের ইন্টারনেট সংযোগ থেকে লোকেশন নেওয়া হয়েছে', 'devApprox': 'লোকেশন আনুমানিক, আইপি অ্যাড্রেসের ভিত্তিতে', 'msgTimer': 'মেসেজ টাইমার', 'timerOff': 'বন্ধ', 't1m': '১ মাস', 't2m': '২ মাস', 't90': '৯০ দিন (সর্বোচ্চ)', 'timerDefault': 'প্রাইভেসি সেটিং অনুযায়ী', 'timerInfo': 'নতুন মেসেজের জন্য সব চ্যাটে প্রযোজ্য। বন্ধ থাকলে আপনার অ্যাকাউন্ট থেকে কোনো মেসেজ নিজে থেকে মুছবে না। একটা চ্যাটের মেনু থেকে শুধু ওই চ্যাটের জন্য আলাদা টাইমার দিতে পারবেন।', 'timerSaved': 'মেসেজ টাইমার আপডেট হয়েছে'},
  'ar': {'server': 'عنوان الخادم', 'phone': 'رقم الجوال', 'name': 'اسمك', 'otp': 'رمز التحقق', 'sendOtp': 'إرسال رمز التحقق', 'verify': 'تأكيد', 'otpSent': 'تم إرسال الرمز', 'noConn': 'تعذّر الاتصال بالخادم', 'incoming': 'يتصل بك', 'decline': 'رفض', 'answer': 'رد', 'nobody': 'لا توجد جهات اتصال بعد', 'audio': 'صوت', 'video': 'فيديو', 'settings': 'الإعدادات', 'theme': 'المظهر', 'system': 'النظام', 'light': 'فاتح', 'dark': 'داكن', 'language': 'اللغة', 'chats': 'الدردشات', 'contacts': 'جهات الاتصال', 'calls': 'المكالمات', 'search': 'بحث', 'typeMsg': 'اكتب رسالة', 'noChats': 'لا توجد دردشات بعد', 'noCalls': 'لا توجد مكالمات بعد', 'newGroup': 'مجموعة جديدة', 'groupName': 'اسم المجموعة', 'create': 'إنشاء', 'bio': 'نبذة', 'save': 'حفظ', 'block': 'حظر', 'report': 'إبلاغ', 'logout': 'تسجيل الخروج', 'phoneH': 'أدخل رقم الجوال', 'nameH': 'أدخل اسمك', 'otpH': 'أدخل الرمز المكوّن من 6 أرقام', 'addContact': 'إضافة جهة اتصال', 'byPhone': 'الجوال', 'byEmail': 'البريد', 'byId': 'المعرّف', 'userId': 'معرّف المستخدم', 'email': 'البريد الإلكتروني', 'nationality': 'الجنسية', 'birth': 'تاريخ الميلاد', 'profile': 'الملف الشخصي', 'security': 'الأمان', 'twoStep': 'التحقق بخطوتين (Google Authenticator)', 'enable': 'تفعيل', 'disable': 'إيقاف', 'secretKey': 'المفتاح السري', 'code': 'رمز من 6 أرقام', 'added': 'تمت إضافة جهة الاتصال', 'notFound': 'المستخدم غير موجود', 'country': 'اختر الدولة', 'verifyEmail': 'تأكيد', 'sendCode': 'إرسال الرمز', 'verified': 'تم التحقق', 'add': 'إضافة', 'copy': 'نسخ', 'twoStepOn': 'التحقق بخطوتين مفعّل', 'scanHint': 'امسح رمز QR أو أدخل المفتاح في Google Authenticator ثم اكتب الرمز', 'codeSent': 'تم إرسال رمز التحقق', 'wrongCode': 'الرمز غير صحيح', 'changeNumber': 'تغيير الرقم', 'changeInfo': 'سينتقل حسابك ومحادثاتك وجهات اتصالك إلى الرقم الجديد. سيصبح الرقم القديم غير صالح في هذا التطبيق.', 'newNumber': 'رقم الجوال الجديد', 'numChanged': 'رقم غير صالح. غيّر المستخدم رقمه.', 'numTaken': 'هذا الرقم مسجّل بالفعل', 'badPhone': 'أدخل رقمًا صحيحًا', 'numDone': 'تم تغيير الرقم بنجاح', 'confirm': 'تأكيد', 'manageDevice': 'إدارة الأجهزة', 'blockedList': 'قائمة المحظورين', 'thisDevice': 'هذا الجهاز', 'lastActive': 'آخر نشاط', 'logoutDevice': 'تسجيل الخروج', 'logoutOthers': 'تسجيل الخروج من جميع الأجهزة الأخرى', 'noBlocked': 'لا يوجد مستخدمون محظورون', 'unblock': 'إلغاء الحظر', 'activeNow': 'نشط الآن', 'blockedInfo': 'لا يستطيع المحظورون مراسلتك أو الاتصال بك.', 'camera': 'الكاميرا', 'gallery': 'المعرض', 'privacy': 'الخصوصية', 'chatCall': 'خصوصية الدردشة والمكالمات', 'privacyChat': 'دردشة خاصة', 'privacyChatInfo': 'تختفي الرسائل بعد المدة المحددة ويُمنع التقاط الشاشة في الدردشات', 'timer': 'تختفي بعد', 'h1': 'ساعة', 'h24': '24 ساعة', 'd7': '7 أيام', 'shotCalls': 'منع لقطة الشاشة في المكالمات', 'callsHdr': 'المكالمات', 'whoCall': 'من يستطيع الاتصال بي', 'everyone': 'الجميع', 'contactsOnly': 'جهات اتصالي', 'nobodyOpt': 'لا أحد', 'lastSeenOpt': 'آخر ظهور وحالة الاتصال', 'inputStatus': 'حالة الكتابة', 'readRec': 'إشعارات القراءة', 'profileHdr': 'خصوصية الملف الشخصي', 'shotProfile': 'منع لقطة الشاشة للملف الشخصي', 'lockProfile': 'قفل الملف الشخصي', 'whoProfile': 'من يستطيع رؤية ملفي الشخصي', 'addingHdr': 'طريقة إضافتي', 'addAfter': 'أضفني بعد قبول الطلبات', 'profileShare': 'مشاركة الملف الشخصي', 'qrCode': 'رمز QR', 'copied': 'تم النسخ', 'cantCall': 'هذا المستخدم لا يقبل مكالماتك', 'requests': 'طلبات الإضافة', 'accept': 'قبول', 'reqSent': 'تم إرسال الطلب. يجب أن يقبل ليتم الربط.', 'online': 'متصل', 'lastSeenAt': 'آخر ظهور', 'typing': 'يكتب…', 'locked': 'هذا الملف الشخصي خاص', 'noReq': 'لا توجد طلبات', 'account': 'الحساب', 'privacySecurity': 'الخصوصية والأمان', 'profilePhoto': 'صورة الملف الشخصي', 'coverPhoto': 'صورة الغلاف', 'personalInfo': 'المعلومات الشخصية', 'contactInfo': 'الاتصال والحساب', 'today': 'اليوم', 'yesterday': 'أمس', 'home': 'الرئيسية', 'noActive': 'لا أحد متصل الآن', 'story': 'القصة', 'myStory': 'قصتي', 'addStory': 'إضافة قصة', 'textStory': 'نص', 'postStory': 'نشر', 'storyText': 'اكتب قصتك', 'caption': 'أضف تعليقًا', 'replyLbl': 'رد', 'viewers': 'شاهدها', 'noViewers': 'لا مشاهدات بعد', 'deleteStory': 'حذف القصة', 'whoStory': 'من يستطيع رؤية قصتي', 'replySent': 'تم إرسال الرد', 'myProfile': 'ملفي الشخصي', 'media': 'الوسائط', 'autoPhotos': 'حفظ الصور المستلمة في المعرض', 'autoVideos': 'حفظ الفيديوهات المستلمة في المعرض', 'mediaInfo': 'تُحفظ الصور والفيديوهات المُرسلة إليك تلقائيًا في معرض هاتفك.', 'sendMedia': 'إرسال وسائط', 'saved': 'تم الحفظ في المعرض', 'recordVideo': 'تسجيل', 'tooBig': 'الملف كبير جدًا (الحد الأقصى 50 ميغابايت)', 'holdToRecord': 'اضغط مطولًا للتسجيل وأفلت للإرسال', 'slideCancel': 'اسحب لليسار للإلغاء', 'register': 'تسجيل', 'regLink': 'مستخدم جديد؟ سجّل', 'loginLink': 'هل لديك حساب؟ سجّل الدخول', 'submit': 'إرسال', 'verifyTitle': 'التحقق من الرقم', 'enterCodeTo': 'أدخل الرمز المرسل إلى', 'resend': 'إعادة إرسال الرمز', 'verifySuccess': 'تم التحقق بنجاح', 'phoneRegistered': 'لقد فتحت حسابًا بهذا الرقم من قبل. يرجى تسجيل الدخول.', 'notRegistered': 'لا يوجد حساب بهذا الرقم. سجّل أولًا.', 'invalidNumber': 'هذا الرقم غير صالح للدولة المحددة', 'badEmail': 'أدخل بريدًا إلكترونيًا صحيحًا', 'fillAll': 'يرجى ملء جميع الحقول', 'emailTaken': 'هذا البريد مستخدم في حساب آخر', 'codeExpired': 'انتهت صلاحية الرمز. اطلب رمزًا جديدًا.', 'tooFast': 'يرجى الانتظار قليلًا قبل الطلب مجددًا', 'accBlocked': 'هذا الحساب محظور', 'logIn': 'تسجيل الدخول', 'faceTitle': 'التحقق من الوجه', 'faceInfo': 'نتحقق من أن شخصًا حقيقيًا يملك هذا الحساب. تُحفظ صور وجهك على خادمنا للتحقق من هويتك عند الدخول من هاتف جديد.', 'faceConsent': 'أوافق على حفظ صور وجهي للتحقق من الهوية', 'faceStep1': 'الخطوة 1: انظر مباشرة إلى الكاميرا', 'faceStep2': 'الخطوة 2: أدر رأسك قليلًا إلى أحد الجانبين', 'faceDone': 'تم قبول الصورتين', 'openCamera': 'افتح الكاميرا', 'cont': 'متابعة', 'faceNoFace': 'لم يتم العثور على وجه. تأكد من وضوح وجهك', 'faceMulti': 'يجب أن يظهر وجه واحد فقط', 'faceBlur': 'الصورة غير واضحة. ثبّت يدك وحاول مجددًا', 'faceQuality': 'جودة الصورة منخفضة. استخدم إضاءة أفضل', 'facePose': 'اتبع وضعية الرأس الموضحة في الخطوة', 'faceMismatch': 'وجهك لا يطابق هذا الحساب', 'faceLocked': 'محاولات كثيرة. حاول بعد 15 دقيقة', 'faceService': 'خدمة الوجه غير متاحة. حاول بعد قليل', 'secShort': 'ث', 'deviceDetails': 'تفاصيل الجهاز', 'devDevice': 'الجهاز', 'devName': 'اسم الجهاز', 'devModel': 'الطراز', 'devOs': 'النظام', 'devLocation': 'الموقع', 'devCountry': 'الدولة', 'devCity': 'المدينة / المنطقة', 'devIsp': 'مزود الإنترنت', 'devIp': 'عنوان IP', 'devLocalIp': 'محلي', 'devNetwork': 'الشبكة', 'devActivity': 'النشاط', 'devFirst': 'أول تسجيل دخول', 'devLastLogin': 'آخر تسجيل دخول', 'devLoggedOut': 'تم تسجيل الخروج', 'devStillIn': 'ما زال مسجّلًا', 'devLastActive': 'آخر نشاط', 'devActive': 'نشط', 'devUnknown': 'غير معروف', 'devLogoutThis': 'تسجيل الخروج من هذا الجهاز', 'devViaServer': 'شبكة محلية: الموقع مأخوذ من اتصال الخادم بالإنترنت', 'devApprox': 'الموقع تقريبي ويعتمد على عنوان IP', 'msgTimer': 'مؤقّت الرسائل', 'timerOff': 'إيقاف', 't1m': 'شهر واحد', 't2m': 'شهران', 't90': '90 يومًا (الحد الأقصى)', 'timerDefault': 'استخدام إعداد الخصوصية', 'timerInfo': 'يُطبّق على الرسائل الجديدة في جميع الدردشات. عند الإيقاف لا تُحذف أي رسالة تلقائيًا من حسابك. يمكنك ضبط مؤقّت مختلف لدردشة واحدة من قائمتها.', 'timerSaved': 'تم تحديث مؤقّت الرسائل'},
  'hi': {'server': 'सर्वर URL', 'phone': 'मोबाइल नंबर', 'name': 'आपका नाम', 'otp': 'OTP कोड', 'sendOtp': 'OTP भेजें', 'verify': 'सत्यापित करें', 'otpSent': 'OTP भेज दिया गया', 'noConn': 'सर्वर से कनेक्ट नहीं हो सका', 'incoming': 'कॉल कर रहा है', 'decline': 'काटें', 'answer': 'उठाएं', 'nobody': 'अभी कोई नहीं', 'audio': 'ऑडियो', 'video': 'वीडियो', 'settings': 'सेटिंग्स', 'theme': 'थीम', 'system': 'सिस्टम', 'light': 'लाइट', 'dark': 'डार्क', 'language': 'भाषा', 'chats': 'चैट', 'contacts': 'संपर्क', 'calls': 'कॉल', 'search': 'खोजें', 'typeMsg': 'संदेश लिखें', 'noChats': 'अभी कोई चैट नहीं', 'noCalls': 'अभी कोई कॉल नहीं', 'newGroup': 'नया ग्रुप', 'groupName': 'ग्रुप का नाम', 'create': 'बनाएं', 'bio': 'बायो', 'save': 'सेव करें', 'block': 'ब्लॉक', 'report': 'रिपोर्ट', 'logout': 'लॉग आउट', 'phoneH': 'मोबाइल नंबर लिखें', 'nameH': 'अपना नाम लिखें', 'otpH': '6 अंकों का कोड लिखें', 'addContact': 'संपर्क जोड़ें', 'byPhone': 'मोबाइल', 'byEmail': 'ईमेल', 'byId': 'यूज़र आईडी', 'userId': 'यूज़र आईडी', 'email': 'ईमेल', 'nationality': 'राष्ट्रीयता', 'birth': 'जन्म तिथि', 'profile': 'प्रोफाइल', 'security': 'सुरक्षा', 'twoStep': 'टू-स्टेप वेरिफिकेशन (Google Authenticator)', 'enable': 'चालू करें', 'disable': 'बंद करें', 'secretKey': 'सीक्रेट की', 'code': '6 अंकों का कोड', 'added': 'संपर्क जोड़ा गया', 'notFound': 'यूज़र नहीं मिला', 'country': 'देश चुनें', 'verifyEmail': 'सत्यापित करें', 'sendCode': 'कोड भेजें', 'verified': 'सत्यापित', 'add': 'जोड़ें', 'copy': 'कॉपी', 'twoStepOn': 'टू-स्टेप वेरिफिकेशन चालू है', 'scanHint': 'QR कोड स्कैन करें या की Google Authenticator में डालें, फिर 6 अंकों का कोड लिखें', 'codeSent': 'वेरिफिकेशन कोड भेजा गया', 'wrongCode': 'कोड गलत है', 'changeNumber': 'नंबर बदलें', 'changeInfo': 'आपका अकाउंट, चैट और संपर्क नए नंबर पर चले जाएंगे। पुराना नंबर इस ऐप में अमान्य हो जाएगा।', 'newNumber': 'नया मोबाइल नंबर', 'numChanged': 'अमान्य नंबर। यूज़र ने अपना नंबर बदल लिया है।', 'numTaken': 'यह नंबर पहले से पंजीकृत है', 'badPhone': 'सही नंबर लिखें', 'numDone': 'नंबर सफलतापूर्वक बदल गया', 'confirm': 'पुष्टि करें', 'manageDevice': 'डिवाइस प्रबंधन', 'blockedList': 'ब्लॉक सूची', 'thisDevice': 'यह डिवाइस', 'lastActive': 'आखिरी सक्रियता', 'logoutDevice': 'लॉग आउट', 'logoutOthers': 'बाकी सभी डिवाइस से लॉग आउट करें', 'noBlocked': 'कोई ब्लॉक यूज़र नहीं', 'unblock': 'अनब्लॉक', 'activeNow': 'अभी सक्रिय', 'blockedInfo': 'ब्लॉक किए गए यूज़र आपको मैसेज या कॉल नहीं कर सकते।', 'camera': 'कैमरा', 'gallery': 'गैलरी', 'privacy': 'गोपनीयता', 'chatCall': 'चैट और कॉल गोपनीयता', 'privacyChat': 'प्राइवेसी चैट', 'privacyChatInfo': 'चुने गए समय के बाद संदेश गायब हो जाते हैं और चैट में स्क्रीनशॉट बंद रहता है', 'timer': 'इसके बाद गायब', 'h1': '1 घंटा', 'h24': '24 घंटे', 'd7': '7 दिन', 'shotCalls': 'कॉल में स्क्रीनशॉट ब्लॉक', 'callsHdr': 'कॉल', 'whoCall': 'मुझे कौन कॉल कर सकता है', 'everyone': 'सभी', 'contactsOnly': 'मेरे संपर्क', 'nobodyOpt': 'कोई नहीं', 'lastSeenOpt': 'लास्ट सीन और ऑनलाइन स्टेटस', 'inputStatus': 'इनपुट स्टेटस', 'readRec': 'रीड रिसीट', 'profileHdr': 'प्रोफाइल गोपनीयता', 'shotProfile': 'प्रोफाइल पर स्क्रीनशॉट ब्लॉक', 'lockProfile': 'प्रोफाइल लॉक', 'whoProfile': 'मेरी प्रोफाइल कौन देख सकता है', 'addingHdr': 'मुझे जोड़ने का तरीका', 'addAfter': 'अनुरोध स्वीकार करने के बाद जोड़ें', 'profileShare': 'प्रोफाइल शेयर', 'qrCode': 'QR कोड', 'copied': 'कॉपी हो गया', 'cantCall': 'यह यूज़र आपके कॉल स्वीकार नहीं करता', 'requests': 'संपर्क अनुरोध', 'accept': 'स्वीकारें', 'reqSent': 'अनुरोध भेजा गया। उनके स्वीकार करने पर आप जुड़ेंगे।', 'online': 'ऑनलाइन', 'lastSeenAt': 'लास्ट सीन', 'typing': 'टाइप कर रहा है…', 'locked': 'यह प्रोफाइल निजी है', 'noReq': 'कोई अनुरोध नहीं', 'account': 'अकाउंट', 'privacySecurity': 'गोपनीयता और सुरक्षा', 'profilePhoto': 'प्रोफाइल फोटो', 'coverPhoto': 'कवर फोटो', 'personalInfo': 'व्यक्तिगत जानकारी', 'contactInfo': 'संपर्क और अकाउंट', 'today': 'आज', 'yesterday': 'कल', 'home': 'होम', 'noActive': 'अभी कोई सक्रिय नहीं', 'story': 'स्टोरी', 'myStory': 'मेरी स्टोरी', 'addStory': 'स्टोरी जोड़ें', 'textStory': 'टेक्स्ट', 'postStory': 'पोस्ट करें', 'storyText': 'अपनी स्टोरी लिखें', 'caption': 'कैप्शन जोड़ें', 'replyLbl': 'जवाब', 'viewers': 'देखने वाले', 'noViewers': 'अभी तक किसी ने नहीं देखा', 'deleteStory': 'स्टोरी हटाएं', 'whoStory': 'मेरी स्टोरी कौन देख सकता है', 'replySent': 'जवाब भेजा गया', 'myProfile': 'मेरी प्रोफाइल', 'media': 'मीडिया', 'autoPhotos': 'मिली तस्वीरें गैलरी में सेव करें', 'autoVideos': 'मिले वीडियो गैलरी में सेव करें', 'mediaInfo': 'दूसरे यूज़र की भेजी तस्वीरें या वीडियो अपने आप फोन की गैलरी में सेव होंगे।', 'sendMedia': 'मीडिया भेजें', 'saved': 'गैलरी में सेव हुआ', 'recordVideo': 'रिकॉर्ड', 'tooBig': 'फ़ाइल बहुत बड़ी है (अधिकतम 50 MB)', 'holdToRecord': 'रिकॉर्ड करने के लिए दबाए रखें, छोड़ने पर भेजा जाएगा', 'slideCancel': 'रद्द करने के लिए बाईं ओर खिसकाएं', 'register': 'रजिस्टर करें', 'regLink': 'नए हैं? रजिस्टर करें', 'loginLink': 'पहले से अकाउंट है? लॉग इन करें', 'submit': 'सबमिट', 'verifyTitle': 'नंबर सत्यापन', 'enterCodeTo': 'जिस नंबर पर कोड भेजा गया', 'resend': 'कोड दोबारा भेजें', 'verifySuccess': 'सत्यापन सफल रहा', 'phoneRegistered': 'आपने इस नंबर से पहले ही अकाउंट खोला है। कृपया लॉग इन करें।', 'notRegistered': 'इस नंबर से कोई अकाउंट नहीं मिला। पहले रजिस्टर करें।', 'invalidNumber': 'चुने गए देश के लिए यह नंबर सही नहीं है', 'badEmail': 'सही ईमेल लिखें', 'fillAll': 'कृपया सभी जानकारी भरें', 'emailTaken': 'यह ईमेल दूसरे अकाउंट में इस्तेमाल हो चुका है', 'codeExpired': 'कोड की अवधि खत्म। नया कोड मँगाएँ।', 'tooFast': 'दोबारा माँगने से पहले थोड़ा रुकें', 'accBlocked': 'यह अकाउंट ब्लॉक है', 'logIn': 'लॉग इन', 'faceTitle': 'फेस वेरिफिकेशन', 'faceInfo': 'हम जाँचते हैं कि इस अकाउंट का मालिक असली व्यक्ति है। नए फोन पर लॉग इन के समय पहचान दोबारा जाँचने के लिए आपके चेहरे की तस्वीरें हमारे सर्वर पर रखी जाती हैं।', 'faceConsent': 'पहचान सत्यापन के लिए मेरे चेहरे की तस्वीरें सहेजने से सहमत हूँ', 'faceStep1': 'चरण 1: सीधे कैमरे की ओर देखें', 'faceStep2': 'चरण 2: सिर को थोड़ा एक तरफ घुमाएँ', 'faceDone': 'दोनों तस्वीरें स्वीकार', 'openCamera': 'कैमरा खोलें', 'cont': 'जारी रखें', 'faceNoFace': 'चेहरा नहीं मिला। चेहरा साफ दिखे ऐसे खींचें', 'faceMulti': 'तस्वीर में केवल एक चेहरा होना चाहिए', 'faceBlur': 'तस्वीर धुँधली है। स्थिर रहकर फिर खींचें', 'faceQuality': 'तस्वीर की गुणवत्ता कम है। बेहतर रोशनी में खींचें', 'facePose': 'चरण में बताई सिर की स्थिति अपनाएँ', 'faceMismatch': 'आपका चेहरा इस अकाउंट से मेल नहीं खाता', 'faceLocked': 'बहुत प्रयास हुए। 15 मिनट बाद फिर कोशिश करें', 'faceService': 'फेस सेवा अभी उपलब्ध नहीं। थोड़ी देर बाद कोशिश करें', 'secShort': 'से', 'deviceDetails': 'डिवाइस विवरण', 'devDevice': 'डिवाइस', 'devName': 'डिवाइस का नाम', 'devModel': 'मॉडल', 'devOs': 'सिस्टम', 'devLocation': 'लोकेशन', 'devCountry': 'देश', 'devCity': 'शहर / क्षेत्र', 'devIsp': 'इंटरनेट प्रदाता', 'devIp': 'आईपी पता', 'devLocalIp': 'लोकल', 'devNetwork': 'नेटवर्क', 'devActivity': 'गतिविधि', 'devFirst': 'पहला लॉग इन', 'devLastLogin': 'आखिरी लॉग इन', 'devLoggedOut': 'लॉग आउट किया', 'devStillIn': 'अभी लॉग इन है', 'devLastActive': 'आखिरी सक्रियता', 'devActive': 'सक्रिय', 'devUnknown': 'अज्ञात', 'devLogoutThis': 'इस डिवाइस से लॉग आउट करें', 'devViaServer': 'लोकल नेटवर्क: लोकेशन सर्वर के इंटरनेट कनेक्शन से ली गई है', 'devApprox': 'लोकेशन अनुमानित है और आईपी पते पर आधारित है', 'msgTimer': 'मैसेज टाइमर', 'timerOff': 'बंद', 't1m': '1 महीना', 't2m': '2 महीने', 't90': '90 दिन (अधिकतम)', 'timerDefault': 'प्राइवेसी सेटिंग के अनुसार', 'timerInfo': 'नए संदेशों पर सभी चैट में लागू। बंद होने पर आपके अकाउंट से कोई संदेश अपने आप नहीं हटेगा। किसी चैट के मेनू से सिर्फ उसी चैट के लिए अलग टाइमर रख सकते हैं।', 'timerSaved': 'मैसेज टाइमर अपडेट हुआ'},
};

final msgTick = ValueNotifier<int>(0);
String get me => prefs.getString('phone') ?? '';
String dm(String a, String b) => ([a, b]..sort()).join('_');
void openCall(BuildContext c, Map r, bool video) =>
    Navigator.push(c, MaterialPageRoute(builder: (_) => CallPage(r, video)));
Future<void> startCall(BuildContext c, List to, bool video) async {
  final r = await post('/call/start', {'to': to, 'video': video});
  if (!c.mounted) return;
  if (r['error'] != null) {
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(t(c, 'cantCall'))));
    return;
  }
  openCall(c, r, video);
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

Future<ImageSource?> pickSource(BuildContext c, String title) => showSheet<ImageSource>(c, title, (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      Widget tile(IconData ic, String label, ImageSource src) => Expanded(
          child: InkWell(
              onTap: () => Navigator.pop(ctx, src),
              child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(10)),
                        child: Icon(ic, size: 30, color: cs.onPrimaryContainer)),
                    const SizedBox(height: 8),
                    Text(label),
                  ]))));
      return IntrinsicHeight(
          child: Row(children: [
        tile(Icons.photo_camera, t(ctx, 'camera'), ImageSource.camera),
        tile(Icons.photo_library, t(ctx, 'gallery'), ImageSource.gallery),
      ]));
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
  final Color? ring;
  const ProfileHeader(this.name, {this.cover, this.avatar, this.onCover, this.onAvatar, this.ring, super.key});
  @override
  Widget build(BuildContext c) {
    final cs = Theme.of(c).colorScheme;
    // cover starts at the very top of the screen (behind the status bar and the transparent app bar)
    final coverH = MediaQuery.of(c).viewPadding.top + kToolbarHeight + 130;
    return SizedBox(
        height: coverH + 52,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: coverH,
              child: GestureDetector(
                  onTap: onCover,
                  child: Container(
                      decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [cs.primary, cs.tertiary]),
                          image: (cover == null || cover!.isEmpty) ? null : DecorationImage(image: NetworkImage('$base$cover'), fit: BoxFit.cover)),
                      child: Stack(children: [
                        // soft dark fade so the status bar icons and back arrow stay readable on any photo
                        Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            height: 110,
                            child: IgnorePointer(
                                child: DecoratedBox(
                                    decoration: BoxDecoration(
                                        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black54, Colors.transparent]))))),
                        if (onCover != null)
                          const Positioned(
                              right: 12,
                              bottom: 12,
                              child: CircleAvatar(radius: 18, backgroundColor: Colors.black45, child: Icon(Icons.photo_camera, color: Colors.white, size: 18))),
                      ])))),
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
                            decoration: BoxDecoration(color: ring ?? cs.surface, shape: BoxShape.circle),
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
          prefixIconColor: cs.primary,
          floatingLabelBehavior: FloatingLabelBehavior.auto,
          floatingLabelStyle: TextStyle(color: cs.primary),
          hintStyle: TextStyle(color: cs.onSurfaceVariant.withOpacity(.65))),
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

Future<Country?> pickCountry(BuildContext c) => showSheet<Country>(c, t(c, 'country'), (_) => const CountrySheet());

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
    final h = MediaQuery.of(c).size.height;
    final avail = h - MediaQuery.of(c).viewInsets.bottom - 170;
    final hh = h * .62 < avail ? h * .62 : avail;
    return SizedBox(
        height: hh,
        child: Column(children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: AppInput(label: t(c, 'search'), icon: Icons.search, onChanged: (v) => setState(() => q = v))),
          Expanded(
              child: ListView(
                  children: list
                      .map((x) => ListTile(
                          leading: Text(x.flag, style: const TextStyle(fontSize: 28)),
                          title: Text(x.name),
                          trailing: Text('+${x.dial}', style: const TextStyle(fontWeight: FontWeight.w600)),
                          onTap: () => Navigator.pop(c, x)))
                      .toList())),
        ]));
  }
}

class PhoneField extends StatefulWidget {
  final TextEditingController ctl;
  final Country country;
  final ValueChanged<Country> onCountry;
  const PhoneField(this.ctl, this.country, this.onCountry, {super.key});
  @override
  State<PhoneField> createState() => _PF();
}

class _PF extends State<PhoneField> {
  @override
  void initState() {
    super.initState();
    widget.ctl.addListener(_r);
  }

  void _r() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.ctl.removeListener(_r);
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final bad = widget.ctl.text.trim().isNotEmpty && !validNational(widget.country.dial, widget.ctl.text);
    return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () async {
                final x = await pickCountry(c);
                if (x != null) widget.onCountry(x);
              },
              child: Container(
                  height: 56,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(border: Border.all(color: Theme.of(c).colorScheme.primary.withOpacity(.5)), borderRadius: BorderRadius.circular(8)),
                  child: Row(children: [
                    Text(widget.country.flag, style: const TextStyle(fontSize: 22)),
                    const SizedBox(width: 6),
                    Text('+${widget.country.dial}'),
                    const Icon(Icons.arrow_drop_down),
                  ]))),
          const SizedBox(width: 8),
          Expanded(
              child: AppInput(
                  controller: widget.ctl,
                  label: t(c, 'phone'),
                  icon: Icons.phone_android,
                  type: TextInputType.phone,
                  errorText: bad ? t(c, 'invalidNumber') : null)),
        ]));
  }
}

/// The ONE text-input component used everywhere in the app (forms, search bars, chat box).
/// Behaviour defined here applies to every input:
///  - idle + empty: the field name sits inside the box (floating label)
///  - tapped: the name floats onto the border line AND the same name shows inside the box as a hint
///  - first character typed: the hint disappears immediately
/// Borders, radius and colours come from the theme (mk), so the look is also changed in one place.
class AppInput extends StatelessWidget {
  final TextEditingController? controller;
  final String? label; // field name (omit for label-less inputs like the chat box)
  final String? hint; // defaults to [label]
  final IconData? icon;
  final Widget? suffix;
  final TextInputType? type;
  final ValueChanged<String>? onChanged, onSubmitted;
  final VoidCallback? onTap;
  final bool editing; // false => no borders, read only (view mode)
  final bool readOnly;
  final EdgeInsetsGeometry margin;
  final int? maxLines, minLines;
  final String? errorText;
  const AppInput({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.icon,
    this.suffix,
    this.type,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.editing = true,
    this.readOnly = false,
    this.margin = EdgeInsets.zero,
    this.maxLines = 1,
    this.minLines,
    this.errorText,
  });

  @override
  Widget build(BuildContext c) => Padding(
      padding: margin,
      child: TextField(
          controller: controller,
          keyboardType: type,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          onTap: onTap,
          readOnly: readOnly || !editing,
          maxLines: maxLines,
          minLines: minLines,
          decoration: InputDecoration(
              labelText: label,
              errorText: errorText,
              hintText: editing ? (hint ?? label) : null,
              prefixIcon: icon == null ? null : Icon(icon),
              suffixIcon: suffix,
              border: editing ? null : InputBorder.none,
              enabledBorder: editing ? null : InputBorder.none,
              focusedBorder: editing ? null : InputBorder.none,
              disabledBorder: editing ? null : InputBorder.none)));
}

/// Thin alias kept for existing call sites; all behaviour lives in [AppInput].
Widget field(TextEditingController c, String l, IconData i,
        {TextInputType? type, Widget? suffix, ValueChanged<String>? onChanged, String? hint, bool editing = true, bool readOnly = false, VoidCallback? onTap}) =>
    AppInput(
        controller: c,
        label: l,
        hint: hint,
        icon: i,
        type: type,
        suffix: suffix,
        onChanged: onChanged,
        editing: editing,
        readOnly: readOnly,
        onTap: onTap,
        margin: const EdgeInsets.only(bottom: 14));

// One shared gap above the system navigation bar for every scrolling page.
// Pages that end with a SectionCard already have an 8px card margin, so they use card: true.
const kGap = 24.0;
EdgeInsets bp(BuildContext c, {double top = 0, double h = 0, bool card = false}) =>
    EdgeInsets.fromLTRB(h, top, h, kGap - (card ? 8 : 0) + MediaQuery.of(c).padding.bottom);

Color pageBg(BuildContext c) {
  final cs = Theme.of(c).colorScheme;
  return Theme.of(c).brightness == Brightness.dark ? cs.surface : cs.surfaceContainerLow;
}

class SectionCard extends StatelessWidget {
  final String? title;
  final List<Widget> children;
  const SectionCard(this.children, {this.title, super.key});
  @override
  Widget build(BuildContext c) {
    final cs = Theme.of(c).colorScheme;
    final dark = Theme.of(c).brightness == Brightness.dark;
    return Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        decoration: BoxDecoration(
            color: dark ? cs.surfaceContainerHigh : cs.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(dark ? .55 : .14), blurRadius: 12, spreadRadius: 1)]),
        child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Material(
                color: Colors.transparent,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (title != null)
                    Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
                        child: Text(title!, style: TextStyle(color: cs.primary, fontWeight: FontWeight.bold, fontSize: 14))),
                  ...children,
                ]))));
  }
}

// ---- presence (online / offline) -------------------------------------------------
// Change these two colours to restyle the status dot everywhere in the app.
const kOnline = Color(0xFF22C55E);
const kOffline = Color(0xFF94A3B8);
final presTick = ValueNotifier<int>(0);
final storyTick = ValueNotifier<int>(0);
final profileTick = ValueNotifier<int>(0); // bump after the user changes their own photo/name
const storyBgs = [Color(0xFF0F8B6D), Color(0xFF6C4DFF), Color(0xFFE5484D), Color(0xFFF59E0B), Color(0xFF0EA5E9), Color(0xFF111827)];

/// Generic row of big icon tiles for bottom sheets: items = [[icon, label, value], ...]
Widget sheetTiles(BuildContext ctx, List<List<dynamic>> items) {
  final cs = Theme.of(ctx).colorScheme;
  return IntrinsicHeight(
      child: Row(
          children: items
              .map((i) => Expanded(
                  child: InkWell(
                      onTap: () => Navigator.pop(ctx, i[2]),
                      child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Container(
                                width: 60,
                                height: 60,
                                decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(10)),
                                child: Icon(i[0] as IconData, size: 30, color: cs.onPrimaryContainer)),
                            const SizedBox(height: 8),
                            Text('${i[1]}'),
                          ])))))
              .toList()));
}

/// Downloads a chat photo/video and stores it in the phone gallery (album "Noor Video Calls").
Future<bool> saveToGallery(String url, bool video) async {
  try {
    final r = await http.get(Uri.parse('$base$url'));
    if (r.statusCode != 200) return false;
    if (!await Gal.hasAccess()) {
      if (!await Gal.requestAccess()) return false;
    }
    if (video) {
      final f = File('${Directory.systemTemp.path}/noor_${DateTime.now().millisecondsSinceEpoch}.mp4');
      await f.writeAsBytes(r.bodyBytes);
      await Gal.putVideo(f.path, album: 'Noor Video Calls');
      await f.delete();
    } else {
      await Gal.putImageBytes(r.bodyBytes, album: 'Noor Video Calls');
    }
    return true;
  } catch (_) {
    return false;
  }
}

/// Settings -> Settings -> Media: saves media that OTHER users send, only if the switch is on,
/// only messages newer than the moment the switch was turned on, and never twice.
Future<void> autoSaveMsg(Map m) async {
  try {
    final type = m['type'];
    if ((type != 'image' && type != 'video') || m['from'] == me || m['url'] == null) return;
    final key = type == 'image' ? 'autoSavePhotos' : 'autoSaveVideos';
    if (prefs.getBool(key) != true) return;
    if (((m['ts'] ?? 0) as num) < (prefs.getInt('${key}Since') ?? 0)) return;
    final saved = prefs.getStringList('savedMedia') ?? [];
    final id = '${m['id']}';
    if (saved.contains(id)) return;
    saved.add(id);
    if (saved.length > 500) saved.removeAt(0);
    await prefs.setStringList('savedMedia', saved);
    await saveToGallery('${m['url']}', type == 'video');
  } catch (_) {}
}

Future<void> addStory(BuildContext c) async {
  final k = await showSheet<String>(
      c,
      t(c, 'addStory'),
      (ctx) => sheetTiles(ctx, [
            [Icons.photo_camera, t(ctx, 'camera'), 'camera'],
            [Icons.photo_library, t(ctx, 'gallery'), 'gallery'],
            [Icons.text_fields, t(ctx, 'textStory'), 'text'],
          ]));
  if (k == null || !c.mounted) return;
  Uint8List? bytes;
  if (k != 'text') {
    if (k == 'camera' && !(await Permission.camera.request()).isGranted) return;
    final x = await ImagePicker().pickImage(source: k == 'camera' ? ImageSource.camera : ImageSource.gallery, maxWidth: 1080, imageQuality: 80);
    if (x == null) return;
    bytes = await x.readAsBytes();
  }
  if (!c.mounted) return;
  final ok = await Navigator.push<bool>(c, MaterialPageRoute(builder: (_) => StoryCompose(bytes)));
  if (ok == true) storyTick.value++;
}

class StoryBubble extends StatelessWidget {
  final String name, label;
  final String? url;
  final bool hasStories, unseen, add;
  final VoidCallback onTap;
  final VoidCallback? onAdd;
  const StoryBubble(this.name, this.label, {this.url, this.hasStories = false, this.unseen = false, this.add = false, required this.onTap, this.onAdd, super.key});
  @override
  Widget build(BuildContext c) {
    final cs = Theme.of(c).colorScheme;
    return GestureDetector(
        onTap: onTap,
        child: SizedBox(
            width: 74,
            child: Column(children: [
              SizedBox(
                  width: 66,
                  height: 66,
                  child: Stack(clipBehavior: Clip.none, children: [
                    Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: hasStories && unseen ? LinearGradient(colors: [cs.primary, cs.tertiary, kOnline], begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
                            border: hasStories && !unseen ? Border.all(color: cs.outlineVariant, width: 2.5) : null),
                        child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(shape: BoxShape.circle, color: cs.surface),
                            child: Avatar(name, r: 27, url: url))),
                    if (add)
                      Positioned(
                          right: -2,
                          bottom: -2,
                          child: GestureDetector(
                              onTap: onAdd,
                              child: Container(
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle, border: Border.all(color: cs.surface, width: 2)),
                                  child: Icon(Icons.add, size: 14, color: cs.onPrimary)))),
                  ])),
              const SizedBox(height: 4),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5)),
            ])));
  }
}

/// Last-seen time shown in the phone's LOCAL time zone.
String fmtSeen(BuildContext c, num ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms.toInt()).toLocal();
  final n = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  final hm = '${two(d.hour)}:${two(d.minute)}';
  final diff = DateTime(n.year, n.month, n.day).difference(DateTime(d.year, d.month, d.day)).inDays;
  if (diff == 0) return '${t(c, 'today')} $hm';
  if (diff == 1) return '${t(c, 'yesterday')} $hm';
  return '${d.year}-${two(d.month)}-${two(d.day)} $hm';
}

Widget presenceText(BuildContext c, Map u) {
  if (u['online'] == true) return Text(t(c, 'online'), style: const TextStyle(color: kOnline, fontWeight: FontWeight.w600));
  if (u['hidden'] == true || (u['last'] ?? 0) == 0) return Text('${u['phone']}');
  return Text('${t(c, 'lastSeenAt')} ${fmtSeen(c, u['last'])}');
}

int contactOrder(dynamic a, dynamic b) {
  final ao = a['online'] == true ? 1 : 0, bo = b['online'] == true ? 1 : 0;
  if (ao != bo) return bo - ao;
  final al = (a['last'] ?? 0) as num, bl = (b['last'] ?? 0) as num;
  if (al != bl) return bl.compareTo(al);
  return '${a['name']}'.compareTo('${b['name']}');
}

/// Full local date and time, e.g. 2026-10-27  14:05:09
String fmtFull(num ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms.toInt()).toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}  ${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
}

String flagOf(dynamic code) {
  final c = '${code ?? ''}'.toUpperCase();
  return c.length == 2 ? String.fromCharCodes(c.codeUnits.map((x) => x + 127397)) : '';
}

/// Icon that turns into a gradient-filled rounded version when [active].
class GradIcon extends StatelessWidget {
  final IconData filled, outline;
  final bool active;
  final double size;
  const GradIcon(this.filled, this.outline, {this.active = false, this.size = 26, super.key});
  @override
  Widget build(BuildContext c) {
    final cs = Theme.of(c).colorScheme;
    if (!active) return Icon(outline, size: size, color: cs.onSurfaceVariant);
    return ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (r) => LinearGradient(colors: [cs.primary, cs.tertiary], begin: Alignment.topLeft, end: Alignment.bottomRight).createShader(r),
        child: Icon(filled, size: size, color: Colors.white));
  }
}

/// IMO-style chat icon: rounded speech bubble with three dots; gradient-filled when selected.
class ChatGlyph extends StatelessWidget {
  final bool active;
  final double size;
  const ChatGlyph({this.active = false, this.size = 28, super.key});
  @override
  Widget build(BuildContext c) {
    final cs = Theme.of(c).colorScheme;
    final dot = active ? Colors.white : cs.onSurfaceVariant;
    return SizedBox(
        width: size,
        height: size,
        child: Stack(alignment: Alignment.center, children: [
          GradIcon(Icons.chat_bubble_rounded, Icons.chat_bubble_outline_rounded, active: active, size: size),
          Padding(
              padding: EdgeInsets.only(bottom: size * .08),
              child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(
                      3,
                      (_) => Container(
                          width: size * .1,
                          height: size * .1,
                          margin: EdgeInsets.symmetric(horizontal: size * .03),
                          decoration: BoxDecoration(shape: BoxShape.circle, color: dot))))),
        ]));
  }
}

class PresenceAvatar extends StatelessWidget {
  final String name;
  final String? url;
  final bool online, hidden;
  final double r;
  const PresenceAvatar(this.name, {this.url, this.online = false, this.hidden = false, this.r = 24, super.key});
  @override
  Widget build(BuildContext c) {
    final ring = Theme.of(c).colorScheme.surface;
    final d = r * .62;
    return SizedBox(
        width: r * 2,
        height: r * 2,
        child: Stack(clipBehavior: Clip.none, children: [
          Avatar(name, r: r, url: url),
          Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                  width: d,
                  height: d,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: online ? kOnline : kOffline,
                      border: Border.all(color: ring, width: 2.5),
                      boxShadow: online ? [BoxShadow(color: kOnline.withOpacity(.55), blurRadius: 6, spreadRadius: 1)] : null))),
        ]));
  }
}

/// Page frame for every profile page: the cover photo runs behind the status bar and a transparent
/// app bar; when the user scrolls down the app bar turns solid so the title stays readable.
class CoverScaffold extends StatefulWidget {
  final String title;
  final List<Widget> actions;
  final Widget header;
  final List<Widget> children;
  const CoverScaffold({required this.title, this.actions = const [], required this.header, required this.children, super.key});
  @override
  State<CoverScaffold> createState() => _CVS();
}

class _CVS extends State<CoverScaffold> {
  final sc = ScrollController();
  bool solid = false;

  @override
  void initState() {
    super.initState();
    sc.addListener(() {
      final v = sc.hasClients && sc.offset > 110;
      if (v != solid) setState(() => solid = v);
    });
  }

  @override
  void dispose() {
    sc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final cs = Theme.of(c).colorScheme;
    final darkPrimary = ThemeData.estimateBrightnessForColor(cs.primary) == Brightness.dark;
    return Scaffold(
        extendBodyBehindAppBar: true,
        backgroundColor: pageBg(c),
        appBar: AppBar(
            title: Text(widget.title),
            backgroundColor: solid ? cs.primary : Colors.transparent,
            foregroundColor: solid ? cs.onPrimary : Colors.white,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            systemOverlayStyle: (!solid || darkPrimary) ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
            actions: widget.actions),
        body: ListView(controller: sc, padding: bp(c, card: true), children: [widget.header, ...widget.children]));
  }
}

Widget infoRow(IconData ic, String label, String? v) =>
    (v == null || v.isEmpty) ? const SizedBox.shrink() : ListTile(leading: Icon(ic), title: Text(v), subtitle: Text(label));

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  prefs = await SharedPreferences.getInstance();
  if (prefs.getString('deviceId') == null) {
    final rnd = Random.secure();
    await prefs.setString('deviceId', List.generate(24, (_) => rnd.nextInt(16).toRadixString(16)).join());
  }
  try {
    String d = '', model = '', brand = '', os = '';
    if (Platform.isAndroid) {
      final i = await DeviceInfoPlugin().androidInfo;
      d = '${i.manufacturer} ${i.model}';
      model = i.model;
      brand = i.brand;
      os = 'Android ${i.version.release} (SDK ${i.version.sdkInt})';
    } else if (Platform.isIOS) {
      final i = await DeviceInfoPlugin().iosInfo;
      d = i.name;
      model = i.utsname.machine;
      brand = 'Apple';
      os = '${i.systemName} ${i.systemVersion}';
    }
    String clean(String v) => v.replaceAll(RegExp(r'[^\x20-\x7E]'), '').trim();
    if (clean(d).isNotEmpty) await prefs.setString('device', clean(d));
    await prefs.setString('devModel', clean(model));
    await prefs.setString('devBrand', clean(brand));
    await prefs.setString('devOs', clean(os));
    await prefs.setString('devPlatform', Platform.operatingSystem);
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
  final srv = TextEditingController(text: 'http://127.0.0.1:3000'), ph = TextEditingController();
  Country cc = countries.first;
  String msg = '';
  bool busy = false;

  Future<void> go() async {
    if (!validNational(cc.dial, ph.text)) return setState(() => msg = t(context, 'invalidNumber'));
    setState(() {
      busy = true;
      msg = '';
    });
    try {
      await prefs.setString('server', srv.text.trim());
      final phone = fullPhone(cc, ph.text);
      final r = await post('/auth/request-otp', {'phone': phone});
      if (r['error'] != null) {
        setState(() => msg = errMsg(context, r['error']));
        return;
      }
      if (!mounted) return;
      final first = await Navigator.push<Map>(
          context,
          MaterialPageRoute(
              builder: (_) => VerifyCodePage(
                  phone: phone,
                  ttl: (r['ttl'] ?? 90) as int,
                  devOtp: r['devOtp'],
                  verify: (code, totp) => post('/auth/verify', {'phone': phone, 'otp': code, 'totp': totp}),
                  resend: () => post('/auth/request-otp', {'phone': phone}))));
      if (first == null || !mounted) return;
      Map? done = first;
      if (first['needFace'] == true) {
        done = await Navigator.push<Map>(
            context, MaterialPageRoute(builder: (_) => FaceVerifyPage(token: '${first['faceToken']}', mode: '${first['mode']}')));
      }
      if (done == null || !mounted) return;
      await finishLogin(context, done);
    } catch (_) {
      if (mounted) setState(() => msg = t(context, 'noConn'));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

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
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            PhoneField(ph, cc, (x) => setState(() => cc = x)),
            if (msg.isNotEmpty)
              Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(msg, style: TextStyle(color: cs.error, fontWeight: FontWeight.w600))),
            FilledButton(
                onPressed: busy ? null : go,
                child: busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(t(c, 'logIn'))),
            TextButton(onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const RegisterPage())), child: Text(t(c, 'regLink'))),
            ExpansionTile(title: Text(t(c, 'server')), shape: const Border(), children: [
              AppInput(controller: srv, label: t(c, 'server'), margin: const EdgeInsets.only(bottom: 14)),
            ]),
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
  String myName = '';
  String? myAvatar;

  Future<void> loadMe() async {
    try {
      final r = await getj('/me');
      if (r is Map && mounted) {
        setState(() {
          myPriv = Map.from(r['privacy'] ?? {});
          myName = '${r['name'] ?? ''}';
          myAvatar = r['avatar'];
        });
      }
    } catch (_) {}
  }


  @override
  void initState() {
    super.initState();
    s = sio.io(base, sio.OptionBuilder().setTransports(['websocket']).setAuth({'token': tok}).build());
    sock = s;
    loadMe();
    profileTick.addListener(loadMe);
    s.on('message', (d) {
      msgTick.value++;
      if (d is Map) autoSaveMsg(d);
    });
    s.on('request', (_) => msgTick.value++);
    s.on('presence', (_) => presTick.value++);
    s.on('story', (_) => storyTick.value++);
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
    profileTick.removeListener(loadMe);
    s.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final pages = [const HomeTab(), const ContactsTab(), const CallsTab(), const SettingsPage()];
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
          NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home), label: t(c, 'home')),
          NavigationDestination(icon: const Icon(Icons.people), label: t(c, 'contacts')),
          NavigationDestination(icon: const Icon(Icons.call), label: t(c, 'calls')),
          NavigationDestination(
              icon: Avatar(myName, r: 13, url: myAvatar),
              selectedIcon: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Theme.of(c).colorScheme.primary, width: 2)),
                  child: Avatar(myName, r: 11, url: myAvatar)),
              label: t(c, 'profile')),
        ]));
  }
}

class HomeTab extends StatefulWidget {
  const HomeTab({super.key});
  @override
  State<HomeTab> createState() => _HT();
}

class _HT extends State<HomeTab> with SingleTickerProviderStateMixin {
  late final TabController tabs = TabController(length: 2, vsync: this);
  List chats = [], people = [], stories = [];
  Map me0 = {};

  @override
  void initState() {
    super.initState();
    tabs.addListener(() {
      if (mounted) setState(() {});
    });
    load();
    msgTick.addListener(load);
    presTick.addListener(load);
    storyTick.addListener(load);
  }

  @override
  void dispose() {
    msgTick.removeListener(load);
    presTick.removeListener(load);
    storyTick.removeListener(load);
    tabs.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final a = await getj('/chats');
      final b = await getj('/users/search?q=');
      final st = await getj('/stories');
      final m = await getj('/me');
      if (a is List && b is List) {
        b.sort(contactOrder);
        if (mounted) {
          setState(() {
            chats = a;
            people = b;
            stories = st is List ? st : [];
            me0 = m is Map ? m : {};
          });
        }
      }
    } catch (_) {}
  }

  bool isOnline(dynamic phone) => people.any((u) => u['phone'] == phone && u['online'] == true);

  Widget chatsList(BuildContext c) => chats.isEmpty
      ? emptyState(c, Icons.chat_bubble_outline, t(c, 'noChats'))
      : ListView(
          children: chats
              .map((i) => ListTile(
                  leading: i['peer'] == null
                      ? Avatar('${i['title']}', url: i['avatar'])
                      : PresenceAvatar('${i['title']}', url: i['avatar'], online: isOnline(i['peer'])),
                  title: Text('${i['title']}'),
                  subtitle: Text('${i['last'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: Text(hm(i['ts']), style: Theme.of(c).textTheme.bodySmall),
                  onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => ChatPage(Map.from(i)))).then((_) => load())))
              .toList());

  Widget activeList(BuildContext c, List act) => act.isEmpty
      ? emptyState(c, Icons.people_outline, t(c, 'noActive'))
      : ListView(
          children: act
              .map((u) => ListTile(
                  leading: PresenceAvatar('${u['name']}', url: u['avatar'], online: true),
                  title: Text('${u['name']}'),
                  subtitle: presenceText(c, u),
                  onTap: () => Navigator.push(
                      c, MaterialPageRoute(builder: (_) => ChatPage({'chat': dm(me, u['phone']), 'title': u['name'], 'peer': u['phone'], 'avatar': u['avatar']}))),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(onPressed: () => startCall(c, [u['phone']], false), icon: const Icon(Icons.call)),
                    IconButton(onPressed: () => startCall(c, [u['phone']], true), icon: const Icon(Icons.videocam)),
                  ])))
              .toList());

  void openStories(BuildContext c, List all, int i) =>
      Navigator.push(c, MaterialPageRoute(builder: (_) => StoryViewer(all, i))).then((_) => load());

  Widget storyRow(BuildContext c) {
    final all = stories.cast<Map>().toList();
    final mine = all.where((g) => g['mine'] == true).toList();
    final others = all.where((g) => g['mine'] != true).toList();
    return Container(
        height: 108,
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Theme.of(c).colorScheme.outlineVariant))),
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), children: [
          StoryBubble('${me0['name'] ?? ''}', t(c, 'myStory'),
              url: me0['avatar'],
              hasStories: mine.isNotEmpty,
              add: true,
              onTap: () => mine.isEmpty ? addStory(c) : openStories(c, all, 0),
              onAdd: () => addStory(c)),
          ...others.map((g) => StoryBubble('${g['name']}', '${g['name']}',
              url: g['avatar'], hasStories: true, unseen: g['unseen'] == true, onTap: () => openStories(c, all, all.indexOf(g)))),
        ]));
  }

  @override
  Widget build(BuildContext c) {
    final act = people.where((u) => u['online'] == true).toList();
    return DefaultTabController(
        length: 2,
        child: Scaffold(
            appBar: AppBar(
                title: const Text('Noor Video Calls'),
                actions: [
                  IconButton(
                      onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const GroupCreate())).then((_) => load()),
                      icon: const Icon(Icons.group_add))
                ],
                toolbarHeight: 48,
                bottom: TabBar(
                    controller: tabs,
                    indicatorSize: TabBarIndicatorSize.tab,
                    indicatorWeight: 3,
                    dividerHeight: 1,
                    tabs: [
                      Tab(height: 40, icon: ChatGlyph(active: tabs.index == 0)),
                      Tab(
                          height: 40,
                          icon: Badge(
                              isLabelVisible: act.isNotEmpty,
                              label: Text('${act.length}'),
                              backgroundColor: kOnline,
                              child: GradIcon(Icons.people_alt_rounded, Icons.people_alt_outlined, active: tabs.index == 1))),
                    ])),
            body: TabBarView(controller: tabs, children: [Column(children: [storyRow(c), Expanded(child: chatsList(c))]), activeList(c, act)])));
  }
}

class ContactsTab extends StatefulWidget {
  const ContactsTab({super.key});
  @override
  State<ContactsTab> createState() => _KT();
}

class _KT extends State<ContactsTab> {
  List users = [];
  int reqCount = 0;
  final q = TextEditingController();
  @override
  void initState() {
    super.initState();
    load();
    msgTick.addListener(load);
    presTick.addListener(load);
  }

  @override
  void dispose() {
    msgTick.removeListener(load);
    presTick.removeListener(load);
    super.dispose();
  }

  Future<void> load() async {
    try {
      final r = await getj('/users/search?q=${Uri.encodeQueryComponent(q.text.trim())}');
      final rq = await getj('/requests');
      if (r is List) r.sort(contactOrder);
      if (mounted) {
        setState(() {
          users = r;
          reqCount = rq is List ? rq.length : 0;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: Text(t(c, 'contacts')), actions: [
          IconButton(
              onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const RequestsPage())).then((_) => load()),
              icon: Badge(isLabelVisible: reqCount > 0, label: Text('$reqCount'), child: const Icon(Icons.notifications_none))),
          IconButton(
              onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const AddContact())).then((_) => load()),
              icon: const Icon(Icons.person_add_alt_1))
        ]),
        body: Column(children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: AppInput(controller: q, label: t(c, 'search'), icon: Icons.search, onChanged: (_) => load())),
          Expanded(
              child: users.isEmpty
                  ? emptyState(c, Icons.people_outline, t(c, 'addContact'))
                  : ListView(
                      children: users
                          .map((u) => ListTile(
                              leading: GestureDetector(
                                  onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => ProfilePage(u['phone']))),
                                  child: PresenceAvatar('${u['name']}', url: u['avatar'], online: u['online'] == true, hidden: u['hidden'] == true)),
                              title: Text('${u['name']}'),
                              subtitle: presenceText(c, u),
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
        msg = ok ? (r['pending'] == true ? t(context, 'reqSent') : '${t(context, 'added')}: ${r['user']['name']}') : t(context, r['error'] == 'number_changed' ? 'numChanged' : (r['error'] == 'invalid_number' ? 'invalidNumber' : 'notFound'));
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
        body: ListView(padding: bp(c, top: 16, h: 16), children: [
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
    getj('/profile?phone=${Uri.encodeQueryComponent(widget.phone)}').then((r) {
      if (!mounted) return;
      setState(() => u = r);
      if (r['blockShot'] == true) setSecure(true);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    if (u['blockShot'] == true) setSecure(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => CoverScaffold(
        title: t(c, 'profile'),
        header: ProfileHeader('${u['name'] ?? ''}', cover: u['cover'], avatar: u['avatar'], ring: pageBg(c)),
        children: [
          const SizedBox(height: 12),
          Center(child: Text('${u['name'] ?? ''}', style: Theme.of(c).textTheme.headlineSmall)),
          if ((u['bio'] ?? '').toString().isNotEmpty) Center(child: Text('${u['bio']}')),
          const SizedBox(height: 12),
          if (u['locked'] == true) SectionCard([ListTile(leading: const Icon(Icons.lock_outline), title: Text(t(c, 'locked')))]),
          if ([u['nationality'], u['birthdate']].any((v) => '${v ?? ''}'.isNotEmpty))
            SectionCard(title: t(c, 'personalInfo'), [
              infoRow(Icons.flag_outlined, t(c, 'nationality'), u['nationality']),
              infoRow(Icons.cake_outlined, t(c, 'birth'), u['birthdate']),
            ]),
          if (u['locked'] != true && [u['phone'], u['email'], u['userId']].any((v) => '${v ?? ''}'.isNotEmpty))
            SectionCard(title: t(c, 'contactInfo'), [
              infoRow(Icons.phone_android, t(c, 'phone'), u['phone']),
              infoRow(Icons.email_outlined, t(c, 'email'), u['email']),
              infoRow(Icons.badge_outlined, t(c, 'userId'), u['userId']),
            ]),
        ]);
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
              child: AppInput(controller: nc, label: t(c, 'groupName'), icon: Icons.group_outlined)),
          Expanded(
              child: ListView(
                  padding: bp(c),
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

  String status = '';
  bool peerOnline = false, peerHidden = false;
  DateTime? typingAt, lastTyping;
  Timer? pt;
  bool secured = false;

  void onTyping(dynamic d) {
    if (d is Map && d['chat'] == id) {
      typingAt = DateTime.now();
      if (mounted) setState(() {});
      Future.delayed(const Duration(seconds: 4), () => mounted ? setState(() {}) : null);
    }
  }

  bool uploading = false;

  // ---- voice messages -------------------------------------------------------------
  final rec = AudioRecorder();
  final amps = <double>[];
  StreamSubscription<Amplitude>? ampSub;
  Timer? recTimer;
  DateTime? recStart;
  Offset? downPos;
  bool hasText = false, recording = false, cancelled = false, holding = false;

  String get recTime {
    final d = recStart == null ? Duration.zero : DateTime.now().difference(recStart!);
    return '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  Future<void> startRec(PointerDownEvent e) async {
    holding = true;
    cancelled = false;
    downPos = e.position;
    try {
      if (!await rec.hasPermission()) return;
      final path = '${Directory.systemTemp.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await rec.start(const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000, sampleRate: 44100, numChannels: 1), path: path);
      if (!holding) {
        await rec.cancel();
        return;
      }
      amps.clear();
      ampSub = rec.onAmplitudeChanged(const Duration(milliseconds: 100)).listen((a) => amps.add(((a.current + 50) / 50).clamp(0.0, 1.0)));
      recStart = DateTime.now();
      recTimer = Timer.periodic(const Duration(milliseconds: 250), (_) => mounted ? setState(() {}) : null);
      setState(() => recording = true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  void moveRec(PointerMoveEvent e) {
    if (!recording || downPos == null) return;
    final c = (e.position.dx - downPos!.dx) < -90;
    if (c != cancelled) setState(() => cancelled = c);
  }

  Future<void> stopRec(bool send) async {
    holding = false;
    if (!recording) return;
    recTimer?.cancel();
    await ampSub?.cancel();
    final ms = DateTime.now().difference(recStart!).inMilliseconds;
    setState(() => recording = false);
    try {
      if (!send || ms < 800) {
        await rec.cancel();
        if (send && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(context, 'holdToRecord'))));
        return;
      }
      final path = await rec.stop();
      if (path == null) return;
      final bytes = await File(path).readAsBytes();
      // 40 bars for the wave picture, each 0..100
      final bars = <int>[];
      if (amps.isNotEmpty) {
        for (var i = 0; i < 40; i++) {
          final a = (i * amps.length / 40).floor(), b = ((i + 1) * amps.length / 40).ceil().clamp(a + 1, amps.length);
          final seg = amps.sublist(a, b);
          bars.add((seg.reduce((x, y) => x > y ? x : y) * 100).round());
        }
      }
      setState(() => uploading = true);
      final r = await http.post(Uri.parse('$base/messages/media'),
          headers: {...hdr, 'Content-Type': 'application/octet-stream', 'X-Chat': id, 'X-Kind': 'voice', 'X-Dur': '$ms', 'X-Wave': bars.join(',')}, body: bytes);
      if (r.statusCode == 401) forceLogout();
      if (r.statusCode != 200 && mounted) {
        String e = 'Error ${r.statusCode}';
        try {
          e = '${jsonDecode(r.body)['error'] ?? e}';
        } catch (_) {}
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e)));
      }
      File(path).delete();
      load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  Future<void> attach() async {
    final k = await showSheet<String>(
        context,
        t(context, 'sendMedia'),
        (ctx) => sheetTiles(ctx, [
              [Icons.photo_camera, t(ctx, 'camera'), 'cam'],
              [Icons.photo_library, t(ctx, 'gallery'), 'gal'],
              [Icons.videocam, t(ctx, 'video'), 'vid'],
              [Icons.fiber_manual_record, t(ctx, 'recordVideo'), 'rec'],
            ]));
    if (k == null) return;
    void snack(String m) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }

    try {
      if ((k == 'cam' || k == 'rec') && !(await Permission.camera.request()).isGranted) return;
      final ip = ImagePicker();
      var kind = 'image';
      XFile? x;
      if (k == 'cam') {
        x = await ip.pickImage(source: ImageSource.camera, maxWidth: 1600, imageQuality: 80);
      } else if (k == 'gal') {
        x = await ip.pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 80);
      } else {
        kind = 'video';
        x = await ip.pickVideo(source: k == 'rec' ? ImageSource.camera : ImageSource.gallery, maxDuration: const Duration(minutes: 2));
      }
      if (x == null) return;
      final bytes = await x.readAsBytes();
      if (bytes.length > 50 * 1024 * 1024) return snack(t(context, 'tooBig'));
      setState(() => uploading = true);
      final r = await http.post(Uri.parse('$base/messages/media'),
          headers: {...hdr, 'Content-Type': 'application/octet-stream', 'X-Chat': id, 'X-Kind': kind}, body: bytes);
      if (r.statusCode == 401) {
        forceLogout();
      } else if (r.statusCode != 200) {
        String e = 'Error ${r.statusCode}';
        try {
          e = '${jsonDecode(r.body)['error'] ?? e}';
        } catch (_) {}
        snack(e);
      }
      load();
    } catch (e) {
      snack('$e');
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  Widget bubbleBody(BuildContext c, Map m) {
    final type = m['type'] ?? 'text';
    if (type == 'text') return Text('${m['text']}');
    if (type == 'voice') return VoiceBubble(m);
    final video = type == 'video';
    final media = GestureDetector(
        onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => MediaViewer('${m['url']}', video))),
        child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: video
                ? Container(width: 220, height: 150, color: Colors.black87, child: const Center(child: Icon(Icons.play_circle_fill, color: Colors.white, size: 54)))
                : Image.network('$base${m['url']}',
                    width: 220,
                    fit: BoxFit.cover,
                    loadingBuilder: (_, w, p) => p == null ? w : const SizedBox(width: 220, height: 150, child: Center(child: CircularProgressIndicator())),
                    errorBuilder: (_, __, ___) => const SizedBox(width: 220, height: 150, child: Center(child: Icon(Icons.broken_image_outlined))))));
    final cap = '${m['text'] ?? ''}';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      media,
      if (cap.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(cap)),
    ]);
  }

  Future<void> chooseTimer() async {
    try {
      final r = await getj('/chats/timer?chat=${Uri.encodeQueryComponent(id)}');
      if (r is! Map || !mounted) return;
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(context, 'timerSaved'))));
    } catch (_) {}
  }

  void onPres() {
    presence();
  }

  void typing() {
    final n = DateTime.now();
    if (lastTyping == null || n.difference(lastTyping!).inSeconds >= 2) {
      lastTyping = n;
      sock?.emit('typing', id);
    }
  }

  Future<void> presence() async {
    if (widget.chat['peer'] == null) return;
    try {
      final r = await getj('/presence?phone=${Uri.encodeQueryComponent(widget.chat['peer'])}');
      if (!mounted || r is! Map) return;
      setState(() {
        peerHidden = r['hidden'] == true;
        peerOnline = r['online'] == true;
        if (r['hidden'] == true) {
          status = '';
        } else if (r['online'] == true) {
          status = t(context, 'online');
        } else if ((r['last'] ?? 0) > 0) {
          status = '${t(context, 'lastSeenAt')} ${fmtSeen(context, r['last'])}';
        }
      });
    } catch (_) {}
  }

  String get statusLine => (typingAt != null && DateTime.now().difference(typingAt!).inSeconds < 4) ? t(context, 'typing') : status;

  @override
  void initState() {
    super.initState();
    tc.addListener(() {
      final h = tc.text.trim().isNotEmpty;
      if (h != hasText && mounted) setState(() => hasText = h);
    });
    load();
    presence();
    msgTick.addListener(load);
    presTick.addListener(onPres);
    sock?.on('typing', onTyping);
    pt = Timer.periodic(const Duration(seconds: 30), (_) => presence());
    if (myPriv['privacyChat'] == true) {
      secured = true;
      setSecure(true);
    }
  }

  @override
  void dispose() {
    msgTick.removeListener(load);
    presTick.removeListener(onPres);
    sock?.off('typing', onTyping);
    pt?.cancel();
    recTimer?.cancel();
    ampSub?.cancel();
    rec.dispose();
    if (secured) setSecure(false);
    super.dispose();
  }

  Future<void> load() async {
    try {
      final r = await getj('/messages?chat=${Uri.encodeQueryComponent(id)}');
      if (!mounted) return;
      setState(() => msgs = r);
      if (r.any((m) => m['from'] != me)) post('/messages/read', {'chat': id});
      for (final m in r) {
        if (m is Map) autoSaveMsg(m);
      }
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
                  widget.chat['peer'] == null
                      ? Avatar('${widget.chat['title']}', r: 18, url: widget.chat['avatar'])
                      : PresenceAvatar('${widget.chat['title']}', r: 18, url: widget.chat['avatar'], online: peerOnline, hidden: peerHidden),
                  const SizedBox(width: 10),
                  Flexible(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text('${widget.chat['title']}', overflow: TextOverflow.ellipsis),
                    if (statusLine.isNotEmpty) Text(statusLine, style: TextStyle(fontSize: 11, color: Theme.of(c).colorScheme.primary)),
                  ])),
                ])),
            actions: [
          IconButton(onPressed: () => startCall(c, others, false), icon: const Icon(Icons.call)),
          IconButton(onPressed: () => startCall(c, others, true), icon: const Icon(Icons.videocam)),
          PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'timer') return chooseTimer();
                await post(v == 'block' ? '/block' : '/report', {'phone': widget.chat['peer'], 'on': true, 'reason': 'report'});
                if (v == 'block' && mounted) Navigator.pop(context);
              },
              itemBuilder: (_) => [
                    PopupMenuItem(value: 'timer', child: Text(t(c, 'msgTimer'))),
                    if (widget.chat['peer'] != null) PopupMenuItem(value: 'block', child: Text(t(c, 'block'))),
                    if (widget.chat['peer'] != null) PopupMenuItem(value: 'report', child: Text(t(c, 'report'))),
                  ]),
        ]),
        body: Column(children: [
          if (uploading) const LinearProgressIndicator(minHeight: 3),
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
                              bubbleBody(c, m),
                              Row(mainAxisSize: MainAxisSize.min, children: [
                                if (m['exp'] != null || m['hide'] != null) Icon(Icons.timer_outlined, size: 11, color: Theme.of(c).colorScheme.onSurfaceVariant),
                                if (m['exp'] != null || m['hide'] != null) const SizedBox(width: 3),
                                Text(hm(m['ts']), style: TextStyle(fontSize: 10, color: Theme.of(c).colorScheme.onSurfaceVariant)),
                                if (mine) const SizedBox(width: 4),
                                if (mine)
                                  Icon(m['seen'] == true ? Icons.done_all : Icons.done,
                                      size: 14, color: m['seen'] == true ? Colors.lightBlue : Theme.of(c).colorScheme.onSurfaceVariant),
                              ]),
                            ])));
                  })),
          SafeArea(
              child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(children: [
                    recording
                        ? const Padding(padding: EdgeInsets.all(12), child: Icon(Icons.fiber_manual_record, color: Colors.red))
                        : IconButton(onPressed: uploading ? null : attach, icon: const Icon(Icons.attach_file)),
                    Expanded(
                        child: recording
                            ? Row(children: [
                                Text(recTime, style: const TextStyle(fontWeight: FontWeight.w600)),
                                const SizedBox(width: 12),
                                Expanded(
                                    child: Text(cancelled ? '✕' : '‹ ${t(c, 'slideCancel')}',
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(color: cancelled ? Colors.red : Theme.of(c).colorScheme.onSurfaceVariant))),
                              ])
                            : AppInput(controller: tc, hint: t(c, 'typeMsg'), onChanged: (_) => typing(), onSubmitted: (_) => send())),
                    const SizedBox(width: 6),
                    hasText
                        ? IconButton.filled(onPressed: send, icon: const Icon(Icons.send))
                        : Listener(
                            onPointerDown: startRec,
                            onPointerMove: moveRec,
                            onPointerUp: (_) => stopRec(!cancelled),
                            onPointerCancel: (_) => stopRec(false),
                            child: CircleAvatar(
                                radius: recording ? 28 : 24,
                                backgroundColor: recording ? Colors.red : Theme.of(c).colorScheme.primary,
                                child: const Icon(Icons.mic, color: Colors.white))),
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
  bool mic = true, cam = false, spk = true, secured = false;
  final t0 = DateTime.now();
  Timer? tm;

  @override
  void initState() {
    super.initState();
    cam = widget.video;
    spk = widget.video;
    if (myPriv['blockCallShot'] == true) {
      secured = true;
      setSecure(true);
    }
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
    if (secured) setSecure(false);
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
    try {
      await post('/auth/logout', {});
    } catch (_) {}
    await prefs.remove('token');
    if (mounted) Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const Login()), (_) => false);
  }

  @override
  Widget build(BuildContext c) {
    final cs = Theme.of(c).colorScheme;
    return CoverScaffold(
        title: t(c, 'myProfile'),
        header: ProfileHeader('${me0['name'] ?? ''}', cover: me0['cover'], avatar: me0['avatar'], onCover: edit, onAvatar: edit, ring: pageBg(c)),
        children: [
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
          SectionCard(title: t(c, 'account'), [
            ListTile(leading: const Icon(Icons.person_outline), title: Text(t(c, 'profile')), trailing: const Icon(Icons.chevron_right), onTap: edit),
            ListTile(
                leading: const Icon(Icons.swap_horiz),
                title: Text(t(c, 'changeNumber')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const ChangeNumberPage()))),
          ]),
          SectionCard(title: t(c, 'privacySecurity'), [
            ListTile(
                leading: const Icon(Icons.lock_outline),
                title: Text(t(c, 'privacy')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const PrivacyPage()))),
            ListTile(
                leading: const Icon(Icons.shield_outlined),
                title: Text(t(c, 'security')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const SecurityPage()))),
          ]),
          SectionCard([
            ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: Text(t(c, 'settings')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const AppSettingsPage()))),
          ]),
          SectionCard(title: t(c, 'theme'), [
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
          ]),
          SectionCard(title: t(c, 'language'), [
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
          SectionCard([
            ListTile(leading: Icon(Icons.logout, color: cs.error), title: Text(t(c, 'logout'), style: TextStyle(color: cs.error)), onTap: logout),
          ]),
        ]);
  }
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
      final src = await pickSource(context, t(context, kind == 'cover' ? 'coverPhoto' : 'profilePhoto'));
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
        profileTick.value++;
      }
    } catch (_) {
      if (mounted) setState(() => msg = t(context, 'noConn'));
    }
  }

  Future<void> save() async {
    final r = await post('/me', {'name': nameC.text, 'bio': bioC.text, 'nationality': natC.text, 'birthdate': birthC.text, 'userId': idC.text.trim()});
    if (r['error'] != null) return setState(() => msg = '${r['error']}');
    if (!mounted) return;
    profileTick.value++;
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
  Widget build(BuildContext c) => CoverScaffold(
        title: t(c, 'profile'),
        actions: [
          AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: editing
                  ? TextButton(key: const ValueKey('save'), style: TextButton.styleFrom(foregroundColor: Colors.white), onPressed: save, child: Text(t(c, 'save')))
                  : IconButton(key: const ValueKey('edit'), onPressed: () => setState(() => editing = true), icon: const Icon(Icons.edit_outlined)))
        ],
        header: ProfileHeader(nameC.text, cover: cover, avatar: avatar, ring: pageBg(c), onCover: () => upload('cover'), onAvatar: () => upload('avatar')),
        children: [
          const SizedBox(height: 12),
          SectionCard(title: t(c, 'personalInfo'), [
            Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  field(nameC, t(c, 'name'), Icons.person_outline, editing: editing),
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
                ])),
          ]),
          SectionCard(title: t(c, 'contactInfo'), [
            Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
                ])),
          ]),
          if (msg.isNotEmpty)
            Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Text(msg, style: TextStyle(color: Theme.of(c).colorScheme.primary, fontWeight: FontWeight.w600))),
        ]);
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
        backgroundColor: pageBg(c),
        appBar: AppBar(title: Text(t(c, 'security')), backgroundColor: pageBg(c)),
        body: ListView(padding: bp(c, top: 8, card: true), children: [
          SectionCard([
            ListTile(
                leading: const Icon(Icons.devices_other),
                title: Text(t(c, 'manageDevice')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const ManageDevices()))),
            ListTile(
                leading: const Icon(Icons.block),
                title: Text(t(c, 'blockedList')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const BlockedList()))),
          ]),
          SectionCard([
            Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
              Expanded(
                  child: GestureDetector(
                      onTap: () => Clipboard.setData(ClipboardData(text: secret!)),
                      child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                          decoration: BoxDecoration(border: Border.all(color: Theme.of(c).colorScheme.outlineVariant), borderRadius: BorderRadius.circular(8)),
                          child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(secret!, maxLines: 1, softWrap: false, style: const TextStyle(fontFamily: 'monospace', fontSize: 16, letterSpacing: 1.2, fontWeight: FontWeight.w600)))))),
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
        ]))]),
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
    const m = {'bad_phone': 'badPhone', 'invalid_number': 'invalidNumber', 'number_taken': 'numTaken', 'wrong_code': 'wrongCode'};
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
        body: ListView(padding: bp(c, top: 16, h: 16), children: [
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
            field(otp, t(c, 'otp'), Icons.lock_outline, type: TextInputType.number),
            if (need2) field(tf, t(c, 'code'), Icons.shield_outlined, type: TextInputType.number),
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
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = await getj('/devices');
      if (mounted && r is List) {
        setState(() {
          items = r;
          loaded = true;
        });
      }
    } catch (_) {}
  }

  Future<void> logoutOthers() async {
    await post('/devices/logout-others', {});
    load();
  }

  String title(Map d) {
    final n = '${d['name'] ?? ''}'.trim();
    return n.isNotEmpty ? n : '${d['brand'] ?? ''} ${d['model'] ?? ''}'.trim();
  }

  @override
  Widget build(BuildContext c) {
    final cs = Theme.of(c).colorScheme;
    final others = items.where((i) => i['active'] == true && i['current'] != true).length;
    return Scaffold(
        backgroundColor: pageBg(c),
        appBar: AppBar(title: Text(t(c, 'manageDevice')), backgroundColor: pageBg(c)),
        body: ListView(padding: bp(c, top: 8, card: true), children: [
          if (loaded && items.isEmpty) SizedBox(height: 300, child: emptyState(c, Icons.devices_other, t(c, 'devUnknown'))),
          ...items.map((d) {
            final active = d['active'] == true;
            final where = [d['city'], d['country']].where((x) => '${x ?? ''}'.isNotEmpty).join(', ');
            final status = active
                ? t(c, 'devActive')
                : (d['loggedOutAt'] != null ? '${t(c, 'devLoggedOut')}  ${fmtFull(d['loggedOutAt'])}' : t(c, 'devLoggedOut'));
            return SectionCard([
              ListTile(
                  leading: CircleAvatar(
                      backgroundColor: active ? cs.primaryContainer : cs.surfaceContainerHighest,
                      child: Icon(Icons.smartphone, color: active ? cs.onPrimaryContainer : cs.onSurfaceVariant)),
                  title: Text('${title(d)}${d['current'] == true ? ' · ${t(c, 'thisDevice')}' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (where.isNotEmpty) Text(where, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Row(children: [
                      Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: active ? kOnline : kOffline)),
                      const SizedBox(width: 6),
                      Flexible(child: Text(status, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: active ? kOnline : null, fontWeight: active ? FontWeight.w600 : null))),
                    ]),
                  ]),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => DeviceDetails(Map.from(d)))).then((_) => load())),
            ]);
          }),
          if (others > 0)
            Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: OutlinedButton.icon(onPressed: logoutOthers, icon: const Icon(Icons.logout), label: Text(t(c, 'logoutOthers')))),
        ]));
  }
}

/// Everything the server really recorded about one device: hardware, IP, location, login / logout times.
class DeviceDetails extends StatefulWidget {
  final Map d;
  const DeviceDetails(this.d, {super.key});
  @override
  State<DeviceDetails> createState() => _DD();
}

class _DD extends State<DeviceDetails> {
  Map get d => widget.d;

  Widget row(BuildContext c, IconData ic, String label, dynamic v) {
    final x = '${v ?? ''}'.trim();
    return ListTile(leading: Icon(ic), title: Text(x.isEmpty ? t(c, 'devUnknown') : x), subtitle: Text(label));
  }

  Future<void> logout() async {
    await post('/devices/logout', {'id': d['id']});
    if (mounted) Navigator.pop(context);
  }

  String cap(String v) => v.isEmpty ? v : v[0].toUpperCase() + v.substring(1);

  @override
  Widget build(BuildContext c) {
    final cs = Theme.of(c).colorScheme;
    final active = d['active'] == true;
    final name = '${d['name'] ?? ''}'.trim().isNotEmpty ? '${d['name']}' : '${d['brand'] ?? ''} ${d['model'] ?? ''}'.trim();
    final pub = d['publicIp'], loc = d['ip'];
    final ip = (pub != null && pub != loc) ? '$pub   (${t(c, 'devLocalIp')}: $loc)' : '${loc ?? pub ?? ''}';
    final place = [d['city'], d['region']].where((x) => '${x ?? ''}'.isNotEmpty).join(', ');
    final country = '${d['country'] ?? ''}'.isEmpty ? null : '${flagOf(d['countryCode'])} ${d['country']}'.trim();
    return Scaffold(
        backgroundColor: pageBg(c),
        appBar: AppBar(title: Text(t(c, 'deviceDetails')), backgroundColor: pageBg(c)),
        body: ListView(padding: bp(c, top: 8, card: true), children: [
          Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                CircleAvatar(radius: 36, backgroundColor: active ? cs.primaryContainer : cs.surfaceContainerHighest, child: Icon(Icons.smartphone, size: 36, color: active ? cs.onPrimaryContainer : cs.onSurfaceVariant)),
                const SizedBox(height: 10),
                Text(name, textAlign: TextAlign.center, style: Theme.of(c).textTheme.titleLarge),
                const SizedBox(height: 6),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 9, height: 9, decoration: BoxDecoration(shape: BoxShape.circle, color: active ? kOnline : kOffline)),
                  const SizedBox(width: 6),
                  Text(active ? t(c, 'devActive') : t(c, 'devLoggedOut'), style: TextStyle(color: active ? kOnline : null, fontWeight: FontWeight.w600)),
                ]),
              ])),
          SectionCard(title: t(c, 'devDevice'), [
            row(c, Icons.badge_outlined, t(c, 'devName'), d['name']),
            row(c, Icons.phone_android, t(c, 'devModel'), '${cap('${d['brand'] ?? ''}')} ${d['model'] ?? ''}'.trim()),
            row(c, Icons.system_update_alt, t(c, 'devOs'), d['os']),
          ]),
          SectionCard(title: t(c, 'devLocation'), [
            row(c, Icons.public, t(c, 'devCountry'), country),
            row(c, Icons.location_on_outlined, t(c, 'devCity'), place),
            row(c, Icons.cell_tower, t(c, 'devIsp'), d['isp']),
            Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: Text(d['viaServer'] == true ? t(c, 'devViaServer') : t(c, 'devApprox'), style: Theme.of(c).textTheme.bodySmall)),
          ]),
          SectionCard(title: t(c, 'devNetwork'), [row(c, Icons.language, t(c, 'devIp'), ip)]),
          SectionCard(title: t(c, 'devActivity'), [
            row(c, Icons.login, t(c, 'devFirst'), d['firstLogin'] == null ? null : fmtFull(d['firstLogin'])),
            row(c, Icons.history, t(c, 'devLastLogin'), d['lastLogin'] == null ? null : fmtFull(d['lastLogin'])),
            row(c, Icons.logout, t(c, 'devLoggedOut'), active ? t(c, 'devStillIn') : (d['loggedOutAt'] == null ? null : fmtFull(d['loggedOutAt']))),
            if (active && d['lastActive'] != null && (d['lastActive'] as num) > 0) row(c, Icons.access_time, t(c, 'devLastActive'), fmtFull(d['lastActive'])),
          ]),
          if (active && d['current'] != true)
            Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: cs.error),
                    onPressed: logout,
                    icon: const Icon(Icons.logout),
                    label: Text(t(c, 'devLogoutThis')))),
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
                      padding: bp(c),
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

class PrivacyPage extends StatefulWidget {
  const PrivacyPage({super.key});
  @override
  State<PrivacyPage> createState() => _PV();
}

class _PV extends State<PrivacyPage> {
  Map pv = {};
  String uid = '', nm = '';
  @override
  void initState() {
    super.initState();
    getj('/me').then((r) {
      if (!mounted) return;
      setState(() {
        pv = Map.from(r['privacy'] ?? {});
        uid = r['userId'] ?? '';
        nm = r['name'] ?? '';
      });
    }).catchError((_) {});
  }

  Future<void> set(String k, dynamic v) async {
    setState(() => pv[k] = v);
    myPriv[k] = v;
    await post('/privacy', {k: v});
  }

  void copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(context, 'copied'))));
  }

  @override
  Widget build(BuildContext c) {
    final cs = Theme.of(c).colorScheme;
    final lv = {'everyone': t(c, 'everyone'), 'contacts': t(c, 'contactsOnly'), 'nobody': t(c, 'nobodyOpt')};
    final tm = {'3600000': t(c, 'h1'), '86400000': t(c, 'h24'), '604800000': t(c, 'd7')};
    final mt = {'86400000': t(c, 'h24'), '604800000': t(c, 'd7'), '2592000000': t(c, 't1m'), '5184000000': t(c, 't2m'), '7776000000': t(c, 't90'), '0': t(c, 'timerOff')};
    Widget hdr(String s, {bool sub = false}) => Padding(
        padding: EdgeInsets.fromLTRB(16, sub ? 12 : 22, 16, 4),
        child: Text(s, style: TextStyle(color: cs.primary, fontWeight: sub ? FontWeight.w600 : FontWeight.bold, fontSize: sub ? 14 : 16)));
    Widget sw(String k, String label, {String? sub}) =>
        SwitchListTile(title: Text(label), subtitle: sub == null ? null : Text(sub), value: pv[k] == true, onChanged: (v) => set(k, v));
    Widget lvl(String k, String label) => ListTile(
        title: Text(label),
        subtitle: Text(lv['${pv[k] ?? 'everyone'}'] ?? ''),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          final v = await pickOption(c, label, '${pv[k] ?? 'everyone'}', lv);
          if (v != null) set(k, v);
        });
    return Scaffold(
        backgroundColor: pageBg(c),
        appBar: AppBar(title: Text(t(c, 'privacy')), backgroundColor: pageBg(c)),
        body: ListView(padding: bp(c, top: 4, card: true), children: [
          SectionCard(title: t(c, 'chatCall'), [
            sw('privacyChat', t(c, 'privacyChat'), sub: t(c, 'privacyChatInfo')),
            if (pv['privacyChat'] == true)
              ListTile(
                  title: Text(t(c, 'timer')),
                  subtitle: Text(tm['${pv['chatTimer'] ?? 86400000}'] ?? ''),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final v = await pickOption(c, t(c, 'timer'), '${pv['chatTimer'] ?? 86400000}', tm);
                    if (v != null) set('chatTimer', int.parse(v));
                  }),
            sw('blockCallShot', t(c, 'shotCalls')),
            ListTile(
                title: Text(t(c, 'msgTimer')),
                subtitle: Text(mt['${pv['msgTimer'] ?? 0}'] ?? t(c, 'timerOff')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final v = await pickOption(c, t(c, 'msgTimer'), '${pv['msgTimer'] ?? 0}', mt);
                  if (v != null) set('msgTimer', int.parse(v));
                }),
            Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 12), child: Text(t(c, 'timerInfo'), style: Theme.of(c).textTheme.bodySmall)),
          ]),
          SectionCard(title: t(c, 'callsHdr'), [
            lvl('whoCanCall', t(c, 'whoCall')),
            lvl('lastSeen', t(c, 'lastSeenOpt')),
            sw('typing', t(c, 'inputStatus')),
            sw('readReceipts', t(c, 'readRec')),
          ]),
          SectionCard(title: t(c, 'profileHdr'), [
            sw('blockProfileShot', t(c, 'shotProfile')),
            sw('lockProfile', t(c, 'lockProfile')),
            lvl('whoSeeProfile', t(c, 'whoProfile')),
            lvl('whoStory', t(c, 'whoStory')),
          ]),
          SectionCard(title: t(c, 'addingHdr'), [
            sw('addByPhone', t(c, 'phone')),
            sw('addById', t(c, 'userId')),
            sw('requireApproval', t(c, 'addAfter')),
          ]),
          SectionCard([
            ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: Text(t(c, 'userId')),
                subtitle: Text(uid),
                trailing: const Icon(Icons.copy, size: 18),
                onTap: () => copy(uid)),
            ListTile(leading: const Icon(Icons.share_outlined), title: Text(t(c, 'profileShare')), onTap: () => copy('Noor Video Calls · $nm · ID: $uid')),
            ListTile(
                leading: const Icon(Icons.qr_code_2),
                title: Text(t(c, 'qrCode')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const QrPage()))),
          ]),
        ]));
  }
}

class QrPage extends StatefulWidget {
  const QrPage({super.key});
  @override
  State<QrPage> createState() => _QP();
}

class _QP extends State<QrPage> {
  String uid = '', nm = '';
  @override
  void initState() {
    super.initState();
    getj('/me').then((r) {
      if (mounted) {
        setState(() {
          uid = r['userId'] ?? '';
          nm = r['name'] ?? '';
        });
      }
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: Text(t(c, 'qrCode'))),
        body: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: uid.isEmpty ? const SizedBox(width: 220, height: 220) : QrImageView(data: 'noor://add?id=$uid', size: 220)),
          const SizedBox(height: 16),
          Text(nm, style: Theme.of(c).textTheme.headlineSmall),
          Text('ID: $uid'),
        ])),
      );
}

class RequestsPage extends StatefulWidget {
  const RequestsPage({super.key});
  @override
  State<RequestsPage> createState() => _RQ();
}

class _RQ extends State<RequestsPage> {
  List items = [];
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = await getj('/requests');
      if (mounted && r is List) setState(() => items = r);
    } catch (_) {}
  }

  Future<void> act(String path, String phone) async {
    await post(path, {'phone': phone});
    load();
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: Text(t(c, 'requests'))),
        body: items.isEmpty
            ? emptyState(c, Icons.notifications_none, t(c, 'noReq'))
            : ListView(
                padding: bp(c),
                children: items
                    .map((u) => ListTile(
                        leading: Avatar('${u['name']}', url: u['avatar']),
                        title: Text('${u['name']}'),
                        subtitle: Text('ID: ${u['userId']}'),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(onPressed: () => act('/requests/decline', u['phone']), icon: const Icon(Icons.close)),
                          FilledButton(onPressed: () => act('/requests/accept', u['phone']), child: Text(t(c, 'accept'))),
                        ])))
                    .toList()),
      );
}

class StoryCompose extends StatefulWidget {
  final Uint8List? bytes;
  const StoryCompose(this.bytes, {super.key});
  @override
  State<StoryCompose> createState() => _SC();
}

class _SC extends State<StoryCompose> {
  final tc = TextEditingController(), cc = TextEditingController();
  int bg = 0;
  bool busy = false;

  Future<void> send() async {
    if (widget.bytes == null && tc.text.trim().isEmpty) return;
    setState(() => busy = true);
    try {
      final r = await post(
          '/stories',
          widget.bytes == null
              ? {'kind': 'text', 'text': tc.text.trim(), 'bg': bg}
              : {'kind': 'image', 'data': base64Encode(widget.bytes!), 'caption': cc.text.trim()});
      if (r['error'] != null) {
        if (mounted) {
          setState(() => busy = false);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${r['error']}')));
        }
        return;
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext c) => Theme(
      data: mk(Brightness.dark),
      child: Scaffold(
          backgroundColor: widget.bytes == null ? storyBgs[bg] : Colors.black,
          body: Stack(fit: StackFit.expand, children: [
            if (widget.bytes != null) Positioned.fill(child: Image.memory(widget.bytes!, fit: BoxFit.contain)),
            if (widget.bytes == null)
              Center(child: Padding(padding: const EdgeInsets.all(24), child: AppInput(controller: tc, label: t(c, 'storyText'), maxLines: 8, minLines: 3))),
            Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                    child: Row(children: [
                  IconButton(onPressed: () => Navigator.pop(c), icon: const Icon(Icons.close, color: Colors.white)),
                  const Spacer(),
                  if (widget.bytes == null)
                    IconButton(onPressed: () => setState(() => bg = (bg + 1) % storyBgs.length), icon: const Icon(Icons.palette_outlined, color: Colors.white)),
                ]))),
            Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                    child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(children: [
                          if (widget.bytes != null) Expanded(child: AppInput(controller: cc, label: t(c, 'caption'))) else const Spacer(),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                              onPressed: busy ? null : send,
                              icon: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send),
                              label: Text(t(c, 'postStory'))),
                        ])))),
          ])));
}

class StoryViewer extends StatefulWidget {
  final List groups;
  final int start;
  const StoryViewer(this.groups, this.start, {super.key});
  @override
  State<StoryViewer> createState() => _SV();
}

class _SV extends State<StoryViewer> with SingleTickerProviderStateMixin {
  late int gi = widget.start;
  int ii = 0;
  late final AnimationController ac;
  final reply = TextEditingController();

  Map get g => widget.groups[gi];
  Map get it => (g['items'] as List)[ii];

  @override
  void initState() {
    super.initState();
    final first = (g['items'] as List).indexWhere((x) => x['seen'] != true);
    ii = first < 0 ? 0 : first;
    ac = AnimationController(vsync: this, duration: const Duration(seconds: 5))
      ..addStatusListener((st) {
        if (st == AnimationStatus.completed) next();
      });
    begin();
  }

  @override
  void dispose() {
    ac.dispose();
    reply.dispose();
    super.dispose();
  }

  void begin() {
    ac.forward(from: 0);
    if (g['mine'] != true) post('/stories/${it['id']}/view', {});
  }

  void next() {
    if (!mounted) return;
    if (ii < (g['items'] as List).length - 1) {
      setState(() => ii++);
      begin();
    } else if (gi < widget.groups.length - 1) {
      setState(() {
        gi++;
        ii = 0;
      });
      begin();
    } else {
      Navigator.pop(context);
    }
  }

  void prev() {
    if (ii > 0) {
      setState(() => ii--);
    } else if (gi > 0) {
      setState(() {
        gi--;
        ii = 0;
      });
    }
    begin();
  }

  Future<void> sendReply() async {
    final txt = reply.text.trim();
    if (txt.isEmpty) return;
    reply.clear();
    FocusScope.of(context).unfocus();
    await post('/messages', {'chat': dm(me, '${g['phone']}'), 'text': '↩ ${t(context, 'story')}: $txt'});
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(context, 'replySent'))));
  }

  Future<void> showViewers() async {
    ac.stop();
    await showSheet<void>(
        context,
        t(context, 'viewers'),
        (ctx) => FutureBuilder<dynamic>(
            future: getj('/stories/${it['id']}/viewers'),
            builder: (_, snap) {
              final l = snap.data;
              if (l is! List) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
              if (l.isEmpty) return Padding(padding: const EdgeInsets.all(24), child: Text(t(ctx, 'noViewers')));
              return ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: ListView(
                      shrinkWrap: true,
                      children: l
                          .map((u) => ListTile(
                              leading: Avatar('${u['name']}', url: u['avatar']),
                              title: Text('${u['name']}'),
                              trailing: Text(fmtSeen(ctx, u['ts']), style: Theme.of(ctx).textTheme.bodySmall)))
                          .toList()));
            }));
    if (mounted) ac.forward();
  }

  Future<void> del() async {
    ac.stop();
    await post('/stories/${it['id']}/delete', {});
    storyTick.value++;
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext c) {
    final items = g['items'] as List;
    final isText = it['kind'] == 'text';
    final bgIdx = ((it['bg'] ?? 0) as num).toInt() % storyBgs.length;
    const white = TextStyle(color: Colors.white, fontWeight: FontWeight.w600);
    return Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) => d.globalPosition.dx < MediaQuery.of(c).size.width / 3 ? prev() : next(),
            onVerticalDragEnd: (d) {
              if ((d.primaryVelocity ?? 0) > 300) Navigator.pop(c);
            },
            onLongPressStart: (_) => ac.stop(),
            onLongPressEnd: (_) => ac.forward(),
            child: Stack(fit: StackFit.expand, children: [
              isText
                  ? Container(
                      color: storyBgs[bgIdx],
                      alignment: Alignment.center,
                      padding: const EdgeInsets.all(28),
                      child: Text('${it['text']}', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w600)))
                  : Image.network('$base${it['url']}', fit: BoxFit.contain, loadingBuilder: (_, w, p) => p == null ? w : const Center(child: CircularProgressIndicator())),
              Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                      child: Padding(
                          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                          child: Column(children: [
                            AnimatedBuilder(
                                animation: ac,
                                builder: (_, __) => Row(
                                    children: List.generate(
                                        items.length,
                                        (i) => Expanded(
                                            child: Padding(
                                                padding: const EdgeInsets.symmetric(horizontal: 2),
                                                child: ClipRRect(
                                                    borderRadius: BorderRadius.circular(2),
                                                    child: LinearProgressIndicator(
                                                        minHeight: 3,
                                                        value: i < ii ? 1.0 : (i == ii ? ac.value : 0.0),
                                                        backgroundColor: Colors.white30,
                                                        valueColor: const AlwaysStoppedAnimation(Colors.white)))))))),
                            const SizedBox(height: 8),
                            Row(children: [
                              Avatar('${g['name']}', r: 18, url: g['avatar']),
                              const SizedBox(width: 10),
                              Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('${g['name']}', style: white),
                                Text(fmtSeen(c, it['ts']), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                              ])),
                              if (g['mine'] == true)
                                PopupMenuButton<String>(
                                    iconColor: Colors.white,
                                    onOpened: ac.stop,
                                    onCanceled: ac.forward,
                                    onSelected: (_) => del(),
                                    itemBuilder: (_) => [PopupMenuItem(value: 'del', child: Text(t(c, 'deleteStory')))]),
                              IconButton(onPressed: () => Navigator.pop(c), icon: const Icon(Icons.close, color: Colors.white)),
                            ]),
                          ])))),
              if (!isText && '${it['caption'] ?? ''}'.isNotEmpty)
                Positioned(
                    left: 0,
                    right: 0,
                    bottom: 96,
                    child: Container(
                        color: Colors.black54,
                        padding: const EdgeInsets.all(12),
                        child: Text('${it['caption']}', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16)))),
              Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: SafeArea(
                      child: g['mine'] == true
                          ? GestureDetector(
                              onTap: showViewers,
                              child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  color: Colors.black38,
                                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                    const Icon(Icons.visibility_outlined, color: Colors.white),
                                    const SizedBox(width: 8),
                                    Text('${it['views'] ?? 0}', style: white),
                                  ])))
                          : Theme(
                              data: mk(Brightness.dark),
                              child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(children: [
                                    Expanded(
                                        child: Focus(
                                            onFocusChange: (f) => f ? ac.stop() : ac.forward(),
                                            child: AppInput(controller: reply, label: t(c, 'replyLbl'), onSubmitted: (_) => sendReply()))),
                                    const SizedBox(width: 6),
                                    IconButton.filled(onPressed: sendReply, icon: const Icon(Icons.send)),
                                  ]))))),
            ])));
  }
}

class AppSettingsPage extends StatelessWidget {
  const AppSettingsPage({super.key});
  @override
  Widget build(BuildContext c) => Scaffold(
        backgroundColor: pageBg(c),
        appBar: AppBar(title: Text(t(c, 'settings')), backgroundColor: pageBg(c)),
        body: ListView(padding: bp(c, top: 4, card: true), children: [
          SectionCard([
            ListTile(
                leading: const Icon(Icons.perm_media_outlined),
                title: Text(t(c, 'media')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const MediaSettingsPage()))),
          ]),
        ]),
      );
}

/// Auto-save of received photos / videos to the phone gallery. Stored on this phone only
/// (prefs keys autoSavePhotos / autoSaveVideos) because the gallery belongs to the device.
class MediaSettingsPage extends StatefulWidget {
  const MediaSettingsPage({super.key});
  @override
  State<MediaSettingsPage> createState() => _MS();
}

class _MS extends State<MediaSettingsPage> {
  bool get photos => prefs.getBool('autoSavePhotos') ?? false;
  bool get videos => prefs.getBool('autoSaveVideos') ?? false;

  @override
  Widget build(BuildContext c) => Scaffold(
        backgroundColor: pageBg(c),
        appBar: AppBar(title: Text(t(c, 'media')), backgroundColor: pageBg(c)),
        body: ListView(padding: bp(c, top: 4, card: true), children: [
          SectionCard(title: t(c, 'media'), [
            SwitchListTile(
                title: Text(t(c, 'autoPhotos')),
                value: photos,
                onChanged: (v) async {
                  await prefs.setBool('autoSavePhotos', v);
                  if (v) await prefs.setInt('autoSavePhotosSince', DateTime.now().millisecondsSinceEpoch);
                  setState(() {});
                }),
            SwitchListTile(
                title: Text(t(c, 'autoVideos')),
                value: videos,
                onChanged: (v) async {
                  await prefs.setBool('autoSaveVideos', v);
                  if (v) await prefs.setInt('autoSaveVideosSince', DateTime.now().millisecondsSinceEpoch);
                  setState(() {});
                }),
            Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Text(t(c, 'mediaInfo'), style: Theme.of(c).textTheme.bodySmall)),
          ]),
        ]),
      );
}

class MediaViewer extends StatefulWidget {
  final String url;
  final bool video;
  const MediaViewer(this.url, this.video, {super.key});
  @override
  State<MediaViewer> createState() => _MV();
}

class _MV extends State<MediaViewer> {
  VideoPlayerController? vc;

  @override
  void initState() {
    super.initState();
    if (widget.video) {
      vc = VideoPlayerController.networkUrl(Uri.parse('$base${widget.url}'))
        ..addListener(() {
          if (mounted) setState(() {});
        })
        ..initialize().then((_) {
          if (mounted) {
            setState(() {});
            vc!.play();
          }
        });
    }
  }

  @override
  void dispose() {
    vc?.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final ok = await saveToGallery(widget.url, widget.video);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? t(context, 'saved') : t(context, 'noConn'))));
  }

  @override
  Widget build(BuildContext c) {
    final v = vc;
    return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, actions: [IconButton(onPressed: save, icon: const Icon(Icons.download))]),
        body: Center(
            child: widget.video
                ? (v != null && v.value.isInitialized
                    ? GestureDetector(
                        onTap: () => v.value.isPlaying ? v.pause() : v.play(),
                        child: Stack(alignment: Alignment.center, children: [
                          AspectRatio(aspectRatio: v.value.aspectRatio, child: VideoPlayer(v)),
                          if (!v.value.isPlaying) const Icon(Icons.play_circle_fill, color: Colors.white70, size: 72),
                          Positioned(left: 0, right: 0, bottom: 0, child: VideoProgressIndicator(v, allowScrubbing: true)),
                        ]))
                    : const CircularProgressIndicator())
                : InteractiveViewer(child: Image.network('$base${widget.url}', fit: BoxFit.contain))));
  }
}

VideoPlayerController? currentVoice;

/// Voice message in a chat bubble: play/pause, real wave picture (recorded levels), time, 1x/1.5x/2x speed.
class VoiceBubble extends StatefulWidget {
  final Map m;
  const VoiceBubble(this.m, {super.key});
  @override
  State<VoiceBubble> createState() => _VB();
}

class _VB extends State<VoiceBubble> {
  VideoPlayerController? vc;
  double speed = 1;

  bool get mine => widget.m['from'] == me;
  bool get heard => (prefs.getStringList('heardVoice') ?? []).contains('${widget.m['id']}');
  int get totalMs => (widget.m['dur'] as num?)?.toInt() ?? 0;

  List<double> get bars {
    final w = '${widget.m['wave'] ?? ''}';
    if (w.isEmpty) return List.generate(32, (i) => .25 + .5 * ((i * 7) % 5) / 5);
    return w.split(',').map((e) => ((int.tryParse(e) ?? 20) / 100).clamp(.08, 1.0).toDouble()).toList();
  }

  String fmt(int ms) => '${(ms ~/ 60000).toString().padLeft(2, '0')}:${((ms ~/ 1000) % 60).toString().padLeft(2, '0')}';

  void markHeard() {
    final l = prefs.getStringList('heardVoice') ?? [];
    final id = '${widget.m['id']}';
    if (!l.contains(id)) {
      l.add(id);
      if (l.length > 500) l.removeAt(0);
      prefs.setStringList('heardVoice', l);
    }
  }

  Future<void> toggle() async {
    if (vc == null) {
      final c0 = VideoPlayerController.networkUrl(Uri.parse('$base${widget.m['url']}'));
      vc = c0;
      c0.addListener(() {
        if (!mounted) return;
        if (c0.value.isCompleted) c0.seekTo(Duration.zero);
        setState(() {});
      });
      await c0.initialize();
      markHeard();
    }
    final v = vc!;
    if (v.value.isPlaying) {
      await v.pause();
    } else {
      if (currentVoice != null && currentVoice != v) await currentVoice!.pause();
      currentVoice = v;
      await v.setPlaybackSpeed(speed);
      await v.play();
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    if (currentVoice == vc) currentVoice = null;
    vc?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final cs = Theme.of(c).colorScheme;
    final v = vc;
    final ready = v != null && v.value.isInitialized;
    final playing = ready && v.value.isPlaying;
    final tot = ready ? v.value.duration.inMilliseconds : totalMs;
    final pos = ready ? v.value.position.inMilliseconds : 0;
    final frac = tot == 0 ? 0.0 : (pos / tot).clamp(0.0, 1.0);
    final b = bars;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      GestureDetector(
          onTap: toggle,
          child: CircleAvatar(radius: 20, backgroundColor: cs.primary, child: Icon(playing ? Icons.pause : Icons.play_arrow, color: cs.onPrimary))),
      const SizedBox(width: 8),
      SizedBox(
          width: 120,
          height: 32,
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            for (var i = 0; i < b.length; i++)
              Expanded(
                  child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: .6),
                      height: 4 + 26 * b[i],
                      decoration: BoxDecoration(color: i / b.length <= frac && pos > 0 ? cs.primary : cs.onSurface.withOpacity(.3), borderRadius: BorderRadius.circular(2)))),
          ])),
      const SizedBox(width: 8),
      Column(mainAxisSize: MainAxisSize.min, children: [
        Text(fmt(playing || pos > 0 ? pos : tot), style: const TextStyle(fontSize: 11)),
        if (ready)
          GestureDetector(
              onTap: () {
                setState(() => speed = speed == 1 ? 1.5 : (speed == 1.5 ? 2 : 1));
                v.setPlaybackSpeed(speed);
              },
              child: Text('${speed == speed.roundToDouble() ? speed.toInt() : speed}x', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: cs.primary))),
      ]),
      if (!mine && !heard && !ready)
        Padding(padding: const EdgeInsets.only(left: 6), child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: kOnline, shape: BoxShape.circle))),
    ]);
  }
}

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});
  @override
  State<RegisterPage> createState() => _RG();
}

class _RG extends State<RegisterPage> {
  final nm = TextEditingController(), nat = TextEditingController(), bd = TextEditingController(), ph = TextEditingController(), em = TextEditingController();
  Country cc = countries.first;
  String msg = '';
  bool busy = false;

  Future<void> submit() async {
    if (nm.text.trim().length < 2 || nat.text.isEmpty || bd.text.isEmpty || em.text.trim().isEmpty || ph.text.trim().isEmpty) {
      return setState(() => msg = t(context, 'fillAll'));
    }
    if (!validNational(cc.dial, ph.text)) return setState(() => msg = t(context, 'invalidNumber'));
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(em.text.trim())) return setState(() => msg = t(context, 'badEmail'));
    setState(() {
      busy = true;
      msg = '';
    });
    try {
      final phone = fullPhone(cc, ph.text);
      final body = {'name': nm.text.trim(), 'nationality': nat.text, 'birthdate': bd.text, 'phone': phone, 'email': em.text.trim()};
      final r = await post('/register/start', body);
      if (r['error'] != null) {
        setState(() => msg = errMsg(context, r['error']));
        return;
      }
      if (!mounted) return;
      final ver = await Navigator.push<Map>(
          context,
          MaterialPageRoute(
              builder: (_) => VerifyCodePage(
                  phone: phone,
                  ttl: (r['ttl'] ?? 90) as int,
                  devOtp: r['devOtp'],
                  verify: (code, _) => post('/register/verify', {'phone': phone, 'otp': code}),
                  resend: () => post('/register/start', body))));
      if (ver == null || !mounted) return;
      final done = await Navigator.push<Map>(
          context, MaterialPageRoute(builder: (_) => FaceVerifyPage(token: '${ver['regToken']}', mode: 'register')));
      if (done == null || !mounted) return;
      await finishLogin(context, done);
    } catch (_) {
      if (mounted) setState(() => msg = t(context, 'noConn'));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: Text(t(c, 'register'))),
        body: ListView(padding: bp(c, top: 16, h: 20), children: [
          AppInput(controller: nm, label: t(c, 'name'), icon: Icons.person_outline, margin: const EdgeInsets.only(bottom: 14)),
          AppInput(
              controller: nat,
              label: t(c, 'nationality'),
              icon: Icons.flag_outlined,
              readOnly: true,
              suffix: const Icon(Icons.arrow_drop_down),
              margin: const EdgeInsets.only(bottom: 14),
              onTap: () async {
                final x = await pickCountry(c);
                if (x != null) setState(() => nat.text = x.name);
              }),
          AppInput(
              controller: bd,
              label: t(c, 'birth'),
              icon: Icons.cake_outlined,
              readOnly: true,
              suffix: const Icon(Icons.calendar_today_outlined, size: 20),
              margin: const EdgeInsets.only(bottom: 14),
              onTap: () async {
                final d = await showDatePicker(
                    context: c, initialDate: DateTime.tryParse(bd.text) ?? DateTime(2000), firstDate: DateTime(1900), lastDate: DateTime.now());
                if (d != null) setState(() => bd.text = d.toIso8601String().substring(0, 10));
              }),
          PhoneField(ph, cc, (x) => setState(() => cc = x)),
          AppInput(controller: em, label: t(c, 'email'), icon: Icons.email_outlined, type: TextInputType.emailAddress, margin: const EdgeInsets.only(bottom: 14)),
          if (msg.isNotEmpty)
            Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(msg, style: TextStyle(color: Theme.of(c).colorScheme.error, fontWeight: FontWeight.w600))),
          FilledButton(
              onPressed: busy ? null : submit,
              child: busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(t(c, 'submit'))),
          TextButton(onPressed: () => Navigator.pop(c), child: Text(t(c, 'loginLink'))),
        ]),
      );
}

/// Code entry page: a ring counts down the seconds left; success draws a ring + check mark.
class VerifyCodePage extends StatefulWidget {
  final String phone;
  final int ttl;
  final String? devOtp;
  final Future<Map> Function(String code, String totp) verify;
  final Future<Map> Function() resend;
  const VerifyCodePage({required this.phone, required this.ttl, this.devOtp, required this.verify, required this.resend, super.key});
  @override
  State<VerifyCodePage> createState() => _VC();
}

class _VC extends State<VerifyCodePage> {
  final code = TextEditingController(), totp = TextEditingController();
  late int total = widget.ttl, left = widget.ttl;
  String? dev;
  String msg = '';
  bool busy = false, need2 = false, ok = false;
  Timer? tm;

  @override
  void initState() {
    super.initState();
    dev = widget.devOtp;
    startTimer();
  }

  @override
  void dispose() {
    tm?.cancel();
    super.dispose();
  }

  void startTimer() {
    tm?.cancel();
    tm = Timer.periodic(const Duration(seconds: 1), (_) {
      if (left > 0 && mounted) setState(() => left--);
    });
  }

  Future<void> submit() async {
    if (code.text.trim().length < 6 || left == 0) return;
    setState(() {
      busy = true;
      msg = '';
    });
    try {
      final r = await widget.verify(code.text.trim(), totp.text.trim());
      if (r['need2fa'] == true) {
        setState(() {
          need2 = true;
          msg = t(context, 'code');
        });
        return;
      }
      if (r['error'] != null) {
        setState(() => msg = errMsg(context, r['error']));
        return;
      }
      tm?.cancel();
      setState(() => ok = true);
      await Future.delayed(const Duration(milliseconds: 2000));
      if (mounted) Navigator.pop(context, r);
    } catch (_) {
      if (mounted) setState(() => msg = t(context, 'noConn'));
    } finally {
      if (mounted && !ok) setState(() => busy = false);
    }
  }

  Future<void> again() async {
    final r = await widget.resend();
    if (!mounted) return;
    if (r['error'] != null) return setState(() => msg = errMsg(context, r['error']));
    setState(() {
      total = left = (r['ttl'] ?? 90) as int;
      dev = r['devOtp'];
      msg = '';
      code.clear();
    });
    startTimer();
  }

  @override
  Widget build(BuildContext c) {
    final cs = Theme.of(c).colorScheme;
    return Scaffold(
        appBar: AppBar(title: Text(t(c, 'verifyTitle'))),
        body: ok
            ? Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                const SuccessCheck(),
                const SizedBox(height: 20),
                Text(t(c, 'verifySuccess'), style: Theme.of(c).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              ]))
            : ListView(padding: bp(c, top: 24, h: 24), children: [
                Text('${t(c, 'enterCodeTo')} +${widget.phone.replaceFirst('+', '')}', textAlign: TextAlign.center),
                const SizedBox(height: 24),
                Center(child: TimerRing(left, total)),
                const SizedBox(height: 28),
                AppInput(controller: code, label: t(c, 'otp'), icon: Icons.lock_outline, type: TextInputType.number, margin: const EdgeInsets.only(bottom: 14)),
                if (need2) AppInput(controller: totp, label: t(c, 'code'), icon: Icons.shield_outlined, type: TextInputType.number, margin: const EdgeInsets.only(bottom: 14)),
                if (dev != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text('OTP: $dev', textAlign: TextAlign.center, style: TextStyle(color: cs.primary))),
                if (msg.isNotEmpty)
                  Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(msg, textAlign: TextAlign.center, style: TextStyle(color: cs.error, fontWeight: FontWeight.w600))),
                FilledButton(
                    onPressed: (busy || left == 0) ? null : submit,
                    child: busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(t(c, 'verifyEmail'))),
                if (left == 0) TextButton(onPressed: again, child: Text(t(c, 'resend'))),
              ]));
  }
}

class TimerRing extends StatelessWidget {
  final int left, total;
  const TimerRing(this.left, this.total, {super.key});
  @override
  Widget build(BuildContext c) {
    final cs = Theme.of(c).colorScheme;
    final low = left <= 10;
    return SizedBox(
        width: 132,
        height: 132,
        child: CustomPaint(
            painter: _RingPainter(total == 0 ? 0 : left / total, cs.primary, cs.tertiary, cs.outlineVariant, low),
            child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.timer_outlined, size: 30, color: low ? cs.error : cs.primary),
              Text('$left${t(c, 'secShort')}', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: low ? cs.error : null)),
            ]))));
  }
}

class _RingPainter extends CustomPainter {
  final double frac;
  final Color c1, c2, bg;
  final bool low;
  _RingPainter(this.frac, this.c1, this.c2, this.bg, this.low);
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.width / 2 - 8;
    canvas.drawCircle(center, r, Paint()..style = PaintingStyle.stroke..strokeWidth = 10..color = bg);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..color = low ? Colors.red : c1;
    if (!low) arc.shader = SweepGradient(colors: [c1, c2, c1]).createShader(Offset.zero & size);
    canvas.drawArc(Rect.fromCircle(center: center, radius: r), -pi / 2, 2 * pi * frac, false, arc);
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.frac != frac || o.low != low;
}

/// Ring that draws itself all the way around, then a check mark draws inside.
class SuccessCheck extends StatefulWidget {
  final double size;
  const SuccessCheck({this.size = 130, super.key});
  @override
  State<SuccessCheck> createState() => _SK();
}

class _SK extends State<SuccessCheck> with SingleTickerProviderStateMixin {
  late final AnimationController ac = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..forward();
  @override
  void dispose() {
    ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => AnimatedBuilder(
      animation: ac,
      builder: (_, __) => CustomPaint(size: Size.square(widget.size), painter: _CheckPainter(ac.value, const Color(0xFF22C55E))));
}

class _CheckPainter extends CustomPainter {
  final double t;
  final Color color;
  _CheckPainter(this.t, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: size.width / 2 - 6);
    canvas.drawArc(rect, -pi / 2, 2 * pi * (t / 0.6).clamp(0.0, 1.0), false, p);
    final cp = ((t - 0.55) / 0.45).clamp(0.0, 1.0);
    if (cp > 0) {
      final w = size.width, h = size.height;
      final path = Path()
        ..moveTo(w * .28, h * .52)
        ..lineTo(w * .44, h * .68)
        ..lineTo(w * .74, h * .36);
      final m = path.computeMetrics().first;
      canvas.drawPath(m.extractPath(0, m.length * cp), p);
    }
  }

  @override
  bool shouldRepaint(_CheckPainter o) => o.t != t;
}

/// Mandatory face check: two live front-camera photos (straight, then head turned).
/// The server validates them and keeps them to re-check the person on a new phone.
class FaceVerifyPage extends StatefulWidget {
  final String token, mode; // mode: register | enroll | verify
  const FaceVerifyPage({required this.token, required this.mode, super.key});
  @override
  State<FaceVerifyPage> createState() => _FV();
}

class _FV extends State<FaceVerifyPage> {
  int step = 0;
  final done = [false, false];
  bool busy = false, consent = false, ok = false;
  String msg = '';

  bool get needConsent => widget.mode != 'verify';

  Future<void> shot() async {
    if (needConsent && !consent) return setState(() => msg = t(context, 'faceConsent'));
    if (!(await Permission.camera.request()).isGranted) return;
    final x = await ImagePicker().pickImage(source: ImageSource.camera, preferredCameraDevice: CameraDevice.front, maxWidth: 900, imageQuality: 85);
    if (x == null) return;
    setState(() {
      busy = true;
      msg = '';
    });
    try {
      final r = await postT('/face/check', {'step': step == 0 ? 'front' : 'turn', 'image': base64Encode(await x.readAsBytes())}, widget.token);
      if (r['ok'] == true) {
        setState(() {
          done[step] = true;
          if (step == 0) step = 1;
        });
      } else {
        setState(() => msg = errMsg(context, r['reason'] ?? r['error']));
      }
    } catch (_) {
      if (mounted) setState(() => msg = t(context, 'noConn'));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> finish() async {
    setState(() {
      busy = true;
      msg = '';
    });
    try {
      final r = await postT(widget.mode == 'register' ? '/register/complete' : '/auth/face-login', {'consent': true}, widget.token);
      if (r['error'] != null) {
        setState(() => msg = errMsg(context, r['error']));
        return;
      }
      setState(() => ok = true);
      await Future.delayed(const Duration(milliseconds: 2000));
      if (mounted) Navigator.pop(context, r);
    } catch (_) {
      if (mounted) setState(() => msg = t(context, 'noConn'));
    } finally {
      if (mounted && !ok) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext c) {
    final cs = Theme.of(c).colorScheme;
    final both = done[0] && done[1];
    return Scaffold(
        appBar: AppBar(title: Text(t(c, 'faceTitle'))),
        body: ok
            ? Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                const SuccessCheck(),
                const SizedBox(height: 20),
                Text(t(c, 'verifySuccess'), style: Theme.of(c).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              ]))
            : ListView(padding: bp(c, top: 16, h: 24), children: [
                Center(
                    child: Container(
                        width: 150,
                        height: 190,
                        decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(100),
                            border: Border.all(color: both ? kOnline : cs.primary, width: 4),
                            color: cs.primaryContainer.withOpacity(.35)),
                        child: Icon(both ? Icons.check_circle : Icons.face_retouching_natural, size: 84, color: both ? kOnline : cs.primary))),
                const SizedBox(height: 18),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  for (var i = 0; i < 2; i++)
                    Container(
                        width: 34,
                        height: 34,
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(shape: BoxShape.circle, color: done[i] ? kOnline : (i == step ? cs.primary : cs.outlineVariant)),
                        child: Center(child: done[i] ? const Icon(Icons.check, color: Colors.white, size: 20) : Text('${i + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))),
                ]),
                const SizedBox(height: 14),
                Text(both ? t(c, 'faceDone') : t(c, step == 0 ? 'faceStep1' : 'faceStep2'),
                    textAlign: TextAlign.center, style: Theme.of(c).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                Text(t(c, 'faceInfo'), textAlign: TextAlign.center, style: Theme.of(c).textTheme.bodySmall),
                if (needConsent) CheckboxListTile(value: consent, onChanged: (v) => setState(() => consent = v ?? false), title: Text(t(c, 'faceConsent'), style: const TextStyle(fontSize: 13)), controlAffinity: ListTileControlAffinity.leading),
                if (msg.isNotEmpty)
                  Padding(padding: const EdgeInsets.only(top: 8, bottom: 8), child: Text(msg, textAlign: TextAlign.center, style: TextStyle(color: cs.error, fontWeight: FontWeight.w600))),
                const SizedBox(height: 10),
                if (!both)
                  FilledButton.icon(onPressed: busy ? null : shot, icon: const Icon(Icons.photo_camera), label: Text(t(c, 'openCamera')))
                else
                  FilledButton(onPressed: busy ? null : finish, child: busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(t(c, 'cont'))),
                if (busy && !both) const Padding(padding: EdgeInsets.only(top: 16), child: LinearProgressIndicator()),
              ]));
  }
}
