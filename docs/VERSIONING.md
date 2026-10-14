# HYP Viewer version policy

## Owner's instruction — 2026-10-14

- The first public release is v0.1.0.
- **Until the owner explicitly asks for a 1.x release, all releases remain v0.MINOR.PATCH.**
- Permitted examples: v0.1.1, v0.2.0, v0.9.9.
- Automated releases refuse v1.0.0 and every other non-zero-major version.
- Changing the policy later requires an explicit user request and a reviewed
  modification of the version validator and release workflow.

## Preferred workflow: release -> update -> verify

The owner prefers to test the app by **installing the official signed release over
the existing installation**. Keep the basic automated CI checks as a safety
gate, then publish a new **0.x patch release**, update Windows and Android
normally, and collect live-site and real-device test feedback. Fix reported
issues in a subsequent 0.x patch rather than rewriting an already released tag.

- Do not silently promote untested public website scraping to guaranteed behavior:
  mock tests and release builds do not prove real external website access.
- Preserve the same persistent Android signing key and increment the Android
  build number on every patch release.
- Do not require a fresh install or deletion of existing library data. If the
  update cannot be installed, collect diagnostics and preserve user backups.
- No 1.x version unless the owner explicitly approves it.

## Requesting the next 0.x version

1. Review and test changes in a PR.
2. Change pubspec.yaml's version and increment its +build integer.
3. Update .github/release-request.txt to the matching tag.
4. Merge to main. The request-file change triggers the release workflow.
5. If signing secrets are present, Windows Setup.exe and signed Android APK
   are released together. Otherwise Windows-only v0.x can be released.
6. To later attach the signed APK, configure the four GitHub Actions secrets
   and manually rerun Publish HYP Viewer 0.x Releases at the SAME commit.

The release workflow creates a lightweight tag at the reviewed main commit and
refuses to overwrite a release tag targeting another commit.

## Security and upgrade continuity

Android must use one durable, backed-up keystore for every official APK.
Never substitute an ephemeral debug key to fill a missing release artifact.
Windows executables currently have no Authenticode signature, so Windows
SmartScreen may warn the publisher is unknown.
