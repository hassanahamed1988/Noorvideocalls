# v2.3 – Forward voice messages

- **Forward** (new) on a received or sent voice message (long press > Forward): choose one or more groups / contacts and send a copy. The forwarded message shows a small "Forwarded" label.
- It follows **Settings > Privacy > Who Can Share My Voice Messages** of the person who ORIGINALLY recorded the message:
  - **Nobody**: no Forward / Share button for the receiver.
  - **Everyone**: everyone you sent the voice message to can forward it.
  - **My Contacts**: only the contacts you ticked can forward it.
  - Your own voice messages can always be forwarded by you. View-once voice messages can never be forwarded.
- Enforced on the **server** too (`POST /messages/forward` answers `share_not_allowed`), so a modified app cannot bypass it. The setting is checked live: changing it also affects voice messages you sent earlier.
- A forwarded copy keeps the original sender's rule, so forwarding cannot be used to pass a voice message to someone the original sender did not allow.

Files: server/index.js, app/lib/main.dart, app/lib/contact_strings.dart, app/pubspec.yaml (2.3.0+14).
