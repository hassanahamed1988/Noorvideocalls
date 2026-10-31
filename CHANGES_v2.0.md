# v2.0 – Permission rules corrected

## Contact Info > Permission (per user)
- **Video Calls / Audio Calls / Chat message**: switch ON = that user may call / message you, OFF = they cannot (their call icons and message box are disabled). You can still call / message them. Same rule for you when they switch it off on their account. (Before, the switches were inverted and blocked YOUR own calls/messages.)
- **Calls Me** (silent mode): OFF = everything looks normal for that user, but their messages show only one tick to them (never delivered / seen) and their calls only appear as a missed call on your side (no call screen, no ringing). Has no effect while Video / Audio / Chat message is already OFF for that user.
- Last Seen & Online Status, Input Status, Read receipts: unchanged.

## Settings > Privacy (all users)
- New **Permission** category: Video Calls, Audio Calls, Chat message. OFF = nobody can call / message this account, ON = everybody can.
- A switch changed inside one user's profile wins for that user only (e.g. main OFF + one user ON = only that user can contact you). Users you never set follow the main Settings.
- Both phones refresh instantly when a switch changes.

## Files
server/index.js, app/lib/main.dart, app/lib/contact_info.dart, app/lib/contact_strings.dart (new texts en/bn/ar/hi).
