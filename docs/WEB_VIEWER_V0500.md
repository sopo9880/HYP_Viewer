# HYP Viewer v0.5.0 WEB Viewer engineering notes

## Mode switching
Clicking the HYP Viewer / WEB Viewer title at the top left changes workspaces. HYP retains existing Home, Reading, Library, Downloads, History, Settings. WEB has Home, Web (site bookmarks), Library, Downloads and Settings. The Reading slot becomes Web.

The WEB library and CBZ files use a separate application-support web_viewer directory, and never modify the original HYP library or gallery archive paths. WEB controller survives tabs and mode switches.

## Public webpage capture
Users add a public HTTPS site, navigate the generic internal WebView manually, then press Detect Images. The browser evaluates a read-only DOM snapshot only when explicitly requested.

Kone-like article pages use the post-article element and the image-view-wrapper elements with sequential image-N IDs. Other websites fall back to article/main DOM regions. Article h1 becomes title; Open Graph and document title are fallbacks. Author, publication time and same-origin canonical URL are saved when available.

A sanitized synthetic 47-image fixture covers Kone DOM structure. The original user-provided HTML is NOT committed because it contains profile information and signed temporary URL parameters.

## Images and download
The actual image CDN may differ from the article host (e.g. gimel.mittere.io). Only discovered public HTTPS image URLs are eligible. Redirects, non-HTTPS, localhost and raw IP addresses are rejected using existing OnlineSourcePolicy. Images are downloaded without session cookies or login secrets; standard referrer is sent. Actual file type is determined from file signatures, not URL extensions; existing CBZ validation runs before storing.

Downloaded CBZs and works are separate from HYP. A reading session uses the existing GalleryReader with WEB-specific page progress tracking. Downloads continue when switching tabs or HYP/WEB modes. This first version's WEB queue is in memory and is not durable over process termination; failures are listed in WEB Downloads and can be requested again from the page. Cancellation is checked between image requests.

The browser reuses the stable Windows WebView2 environment from v0.4.25 without native request interception. Login restrictions and access limits are not bypassed.

## Validation
PR CI must validate generated localizations, flutter analyze, flutter test, Android/Windows debug builds and Windows setup. Synthetic tests check 47 image ordering, malicious URL rejection, CDN image type identification and separation from the original HYP storage.

Real-site download and WebView operation remain unverified until the user tests the published official release on physical devices. Official Android APK is signed once in main CI and reused by release workflow without rebuilding.
