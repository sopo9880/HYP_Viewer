# Approved HYP Viewer app icon

Source: the neon blue/purple HYP eye-and-open-book app icon approved in chat.

The source JPEG is stored as eight raw byte fragments, because binary blobs
were imported individually and verified against the original bytes. These are
**not separate icons**. Reconstruct it by concatenating parts 00-07, in order.
The source is 160x160 JPEG and has SHA-256
`08679c28e4b8bda686577196f05f0903bbcf1bc86b7be6a06e5f5837adf2e03a`.

`python scripts/apply_app_icons.py --platform android` and
`python scripts/apply_app_icons.py --platform windows`
reassemble and validate the source automatically on CI after Flutter generates
its host projects, before any platform build. This updates Android launcher
PNGs, Windows runner ICO, and the Flutter tray icon asset.

To change the design later, write a new
`assets/icons/hyp_app_icon.jpg` source; the build script will prefer it
over the original fragments. Do not change user-library or settings paths.
