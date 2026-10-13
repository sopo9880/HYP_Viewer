# Online image sources

HYP Viewer only loads a gallery from a user-configured, authorized HTTPS
image source. No third-party gallery scraper is bundled.

## Configure

In the app, enter a URL template containing exactly one {workId} marker:

    https://gallery.example.org/galleries/{workId}.json

For library work ID 2711759, the program requests /galleries/2711759.json
on the configured host. The response is a v1 JSON manifest:

    {
      "schemaVersion": 1,
      "workId": "2711759",
      "title": "Example work",
      "allowDownload": true,
      "pages": ["/images/2711759/001.jpg", "/images/2711759/002.jpg"]
    }

The manifest declares whether the owner allows offline downloads. If
allowDownload is false, online viewing works but download is disabled.

The HTTPS pages must use the SAME hostname as the manifest, without redirects
or embedded credentials. Private/local IP literals and non-HTTPS URLs are
rejected. Image responses must carry an image MIME type.

## Reader and download

Use "온라인 읽기" to stream pages and preserve reading progress.
Use "다운로드" for a separately confirmed, authorized local download.
The downloaded gallery is stored as a CBZ in application support storage,
preserving it across normal app upgrades.

The app shows downloaded page count and MB, and offers a cancellation button.
A failed or cancelled operation does not replace an existing offline CBZ.
The app limits each image to 35 MB, the whole gallery download to 165 MB, and
the resulting CBZ to 180 MB. Free disk space is not proactively measured;
insufficient space produces an error and temporary files are cleaned up.

Use "오프라인 읽기" to access the saved CBZ without internet.
Alternatively import your own CBZ/ZIP via "CBZ/ZIP 연결".

## Backups and rights

JSON exports contain reading progress, source video URL, favorites and
other work metadata; they intentionally exclude downloaded CBZ image files.
Transfer your own authorized image archives separately when changing devices.

Do not enter API secrets, cookies or private access tokens in URL templates.
Use only image sources you control or have permission to access and download.
The app does not bypass DRM, authentication, rate limits or site restrictions.
