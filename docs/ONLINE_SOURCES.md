# Online reading and optional sources

HYP Viewer has **two separate remote reading flows**. They are not
interchangeable.

## 1. Built-in Hitomi online reader (no configuration required)

1. Save a numeric gallery/work ID in the library.
2. Select **앱 내 온라인 읽기** on its work card.
3. The app requests public gallery metadata, resolves individual image URLs
   based on the site's public routing information, and streams them into the
   built-in reader. Zoom, swiping and page-progress saving are supported.
4. If direct reading fails or you prefer the site's browser, use
   **웹 리더 · 시작 페이지 선택** to open a web page instead.

The external web address is fixed by the app:

    https://hitomi.la/reader/{workId}.html#1
    https://hitomi.la/reader/{workId}.html#2-3
    https://hitomi.la/reader/{workId}.html#3-4

This URL is a **web page**, not a JSON image manifest. The fragment is handled
by the website and may change. Page navigation performed in an external
browser cannot be synchronized back into the app.

Online access can fail if the source is unavailable, its format changes, or
the request is blocked. No login, DRM, paywall or bot protection bypass is
implemented. The app does not package third-party images. Only read
content that you have permission to access.

The built-in Hitomi source is for streaming in the reader. It does **not**
automatically enable bulk downloads.

## 2. Optional authorized JSON source for offline CBZ files

If you control or have permission to use a compatible image server, add an
HTTPS URL template in Settings, containing exactly one {workId} marker:

    https://gallery.example.org/galleries/{workId}.json

For work ID 2711759, this requests /galleries/2711759.json.
The server must respond with JSON:

    {
      "schemaVersion": 1,
      "workId": "2711759",
      "title": "Example work",
      "allowDownload": true,
      "pages": ["/images/2711759/001.jpg", "/images/2711759/002.jpg"]
    }

Downloads only work if the source explicitly returns allowDownload=true.
This URL template is **not required** for the default in-app reader.

The HTTPS images must use the same hostname as the JSON manifest, without
redirects or embedded credentials. IP literals and non-HTTPS URLs are rejected.
Image responses must carry an image MIME type.

## Downloads and security

Use **JSON 소스 다운로드** for a separately confirmed, authorized CBZ
download. The app shows a page count, transfer progress and a cancellation
button. A failed or canceled attempt does not replace an existing CBZ.

Each image is limited to 35 MB, combined images to 165 MB, and the
resulting archive to 180 MB. Insufficient disk space produces an error;
temporary files are cleaned up.

Use **오프라인 읽기** for saved CBZ files; alternatively import your own
CBZ/ZIP files via **CBZ/ZIP 연결**.

JSON backups preserve library metadata and reading progress, but deliberately
exclude downloaded CBZ files. Keep your own archives separately during device
migration. Do not put passwords, API keys, cookies or session tokens in source
URLs. The app does not circumvent site restrictions.

## Technical reference and attribution

The gallery image routing scheme was independently ported to Dart based on
the public source of [lanyeeee/hitomi-downloader](https://github.com/lanyeeee/hitomi-downloader)
(MIT license, Copyright 2025 lanyeeee). Attribution and MIT terms are included
in [third-party notices](THIRD_PARTY_NOTICES.md).
