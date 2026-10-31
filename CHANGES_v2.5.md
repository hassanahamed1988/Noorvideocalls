# v2.5 – Documents

- **Send documents**: attach menu > **Document**. PDF, Word (doc/docx), Excel (xls/xlsx), PowerPoint (ppt/pptx), TXT, CSV, RTF, OpenDocument (odt/ods/odp), ZIP, RAR, 7Z. Maximum **25 MB**. One tap from the picker to sent: no extra screens.
- **Document bubble**: coloured type tag (PDF / DOCX / XLS ...), file name, size.
- **Download + open**: tap the bubble. A progress ring shows the download, the file is saved in the phone's **Downloads** folder in the background ("Saved to Downloads"), then the phone's own **"Open with"** chooser appears (Google Drive, PDF viewers, Office apps ...). Tapping a file that is already in Downloads opens the chooser immediately, without downloading again. Works for files you sent and files you received.
- Documents can be **forwarded** (long press > Forward, or swipe left/right) and **shared**; they show in chat lists as "📄 name", in notifications, and in Contact Info > Manage Storage > Documents.
- Photos / videos are unchanged (Save to gallery already existed).

## Server
- `POST /messages/media` with `X-Kind: document` + `X-Name` (URL-encoded file name). Checks the extension, the 25 MB limit and that the file content really matches its type (so a program renamed to .pdf is refused). Stored as a random file name; the original name is kept in the message (`name`, `size`).
- Document files are served with `Content-Disposition: attachment` and `nosniff`, never as a web page.
- `POST /messages/forward` also forwards documents.

## Android (branding/MainActivity.kt) – copy it over the project's MainActivity.kt as before
- New channel `noor/files`: file picker (ACTION_OPEN_DOCUMENT), save into Downloads (MediaStore on Android 10+, plain Downloads file + storage permission on Android 9 and older), existence check, and the "Open with" chooser.

Needs: restart the server; rebuild the app. No new Flutter packages.
