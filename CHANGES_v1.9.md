# v1.9 – Account management, Settings & Security, Switch Account

## Account
- **Delete Account**: warning popup → type DELETE → phone's own fingerprint/screen-lock check (→ Authenticator code if Two-Step is on) → server erases profile, photos, face photos, stories, contacts, requests, devices, sessions, chat/call history of that user. Messages already sent stay in the other person's chat as "Deleted User" (no name, photo or number; the number is replaced by a random ID). Empty groups vanish. Reports against the user are kept anonymously for 90 days. Only a one-way hash of the number is kept: same number can register again after **7 days** (never, if the account was banned). Old login tokens can never work on a re-created account.
- **Deactivate Account**: data untouched; hidden from search, profile, presence, calls, stories; chats show "Deactivated User" without photo. Signing in shows a Reactivate screen (also Logout / Delete). Reactivate = everything visible again.

## UI
- Nav-bar Profile tab → page title **Settings** ("My Profile" removed); Settings > Profile → **Profile Details**.
- "Privacy & Security" → **Settings & Security**: Account & Security, Privacy, Media Manage (old "Settings" option, goes straight to media auto-save).
- **Account & Security**: Device Manage, Blocked List, Fingerprint, Two-Step Verification, Deactivate Account, Delete Account.
- **Fingerprint** switch uses the phone's native authentication only (`local_auth`: fingerprint/face or device PIN/pattern/password). Locks every time the app is opened or returns from background (camera/gallery/share/permission trips are exempt).
- **Switch Account** (Settings > Account, next to Change Mobile Number): max 2 accounts, OTP only to add, each with its own server session/token and its own local settings. Only the active account receives messages/calls.

## Files
server/index.js (new routes /account/deactivate, /account/reactivate, /account/delete; visibility rules), app/lib/main.dart, app/lib/account_strings.dart (new, en/bn/ar/hi), app/lib/contact_info.dart.

## Navigation & Back button
- Calls History: tapping a person's name, photo or the row opens that person's Chat Screen (single-person calls; deleted/deactivated users open their chat with the "Deleted/Deactivated User" label).
- Contacts, Calls and Profile (Settings) top bars have a Back icon that returns to Home.
- Android system Back does the same: on Contacts/Calls/Profile it goes to Home first, on Home it leaves the app. Pushed pages (chat, settings sub-pages…) keep the normal pop behaviour for both the Back icon and the system button.

## Video call & ringing
- **Video call screen**: real full screen (system bars hidden). Outgoing video call shows YOUR live camera full-screen while it rings (name + Calling/Ringing on top); once answered the other person fills the screen and your camera is the small picture (tap it = swap big/small, long-press = hide). Tap the picture to hide/show buttons (they auto-hide 5 s after connecting). New switch-camera (front/back) button. If camera permission is denied the call continues as audio.
- **Sounds**: incoming call rings with the phone's default ringtone (looping, follows ring volume) unless you picked another tone / "Silent" in Contact Info > Call Ringtone; it stops on answer / decline / caller hang-up. Outgoing call plays the ringback tone only while the other phone is really ringing (earpiece for audio calls, loudspeaker for video calls), stops on answer, and ends with a busy tone (declined / no answer) or a short beep (after a conversation). All from Android system tones — no extra audio files.
- **Minimize icon**: two opposite arrows (close_fullscreen) instead of the down arrow.
- Native part is in branding/MainActivity.kt (noor/sound channel: ringback, stopRingback, endtone) — make sure your workflow still copies this file.

## Chat call history
- Calls appear inside the chat timeline between the messages, as centered cards: type (voice/video), status, direction, **date + time**, and for completed calls the **real duration** (answered → ended).
- Status follows the real call state (server `callState`): Completed, In progress, Missed, Declined, Unanswered (the other phone rang but nobody answered), Failed (never connected), Ringing, Calling. Calls whose app closed/crashed are closed automatically after 75 s (unanswered) so they never stay "ringing".
- Tick indicator (outgoing calls): 1 grey tick = sent/calling; 2 grey ticks = reached the other phone (ringing / unanswered / declined); 2 blue ticks = answered; red single tick = failed. Incoming calls show a received / missed arrow.
- Time/date are stored on the server for every call (start, answered, ended). "Clear chat history" also clears the call entries. New endpoint: `GET /calls/chat?chat=<dm>`; both phones refresh instantly on call start / ringing / answer / end.

## Voice recording & animation
- **Tap-to-record** (added, hold-to-record is unchanged): a quick tap on the mic starts recording and it keeps going after you lift your finger. The bar then shows trash, timer, a live sound wave and a Send button. Holding the mic still records while held, sends on release, and slide left cancels, exactly as before.
- **Swipe to cancel** also works in tap mode: swipe the recording bar to the left (the bar follows your finger and fades); past the threshold the recording is cancelled. Tapping the trash cancels too.
- **Animation**: a cancelled/deleted recording lifts up, tilts, blurs and fades away to the left with a few dust specks drifting off, like it is blown away by the wind. The same animation plays when a sent message (voice or any other) is erased with "Erase for both" in a private chat: the bubble flies away, then the gap closes smoothly, then the server erases it.
- Note: message erase exists only in private chats (already so before); in normal chats you cannot delete a sent message, so there the animation applies to recordings only.

## Tap-recording panel, message action sheet, Delete for everyone / for me
- **Tap-to-record panel** (after a quick tap on the mic): timer, large live wave, red **trash**, **Pause / Resume** pill (really pauses the recorder; the timer and wave stop), green **Send**. Swipe the wave area left to cancel. Hold-to-record keeps its old bar (now with a pulsing dot).
- **Long-press a message / photo / video / voice**: the message is highlighted and a premium action sheet slides up above the navigation bar: preview of the message, then Reply, Copy (text), Share, Save (photo/video → gallery), Details, Delete.
- **Delete** opens "Delete message?": **Delete for everyone** (only your own messages), **Delete for me**, Cancel. The bubble is blown away first, then deleted.
  - Delete for me: hidden only on your phone (server `delFor`).
  - Delete for everyone: media file erased on the server, content removed, both chats show "This message was deleted" / "You deleted this message"; replies to it and the chat-list preview show the same note. In a Privacy Chat nothing is left behind (message removed completely).
  - New endpoint `POST /messages/delete {chat,id,scope:'me'|'all'}`. Works for text, photo, video and voice in every chat (direct and group).
- Not included: "also delete media from the gallery" checkbox (the `gal` plugin cannot delete gallery files), view-once "1" icon, multi-select.

## Multi-select delete, gallery copy delete, View-once voice
- **Select several messages**: long-press > "Select", then tap more messages (ticks + highlight). The top bar becomes count + Reply (1 message) / Copy (text only) / Delete. Back or X clears the selection. "Delete for everyone" is offered only when every selected message is yours; the server deletes nothing unless all are yours. `POST /messages/delete` now takes `ids: [...]`.
- **"Also delete the saved copy from the phone gallery"** checkbox in the delete dialog. It appears only when at least one selected photo/video was saved to the gallery by this app (auto-save or the Save button): the app remembers the gallery item of each saved message (new native channel `noor/gallery` in branding/MainActivity.kt) and erases it with Delete for me / for everyone. Works for copies this install saved (Android 10+); if the system refuses (e.g. after a reinstall) the gallery item simply stays.
- **View-once voice**: in the tap-recording panel the round **1** switch (direct chats only). The receiver sees "Tap to play once"; the recording is downloaded, the server erases it immediately (`POST /messages/opened`) and it plays one time only (pause/resume allowed). Afterwards both sides see "Opened". The sender never receives the file back and sees "not opened yet / Opened". Not available in group chats. Screenshots / screen recording are not blocked.
