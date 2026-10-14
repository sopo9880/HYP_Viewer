# HYP Viewer v0.1.9 validation

## Rule-based multi-work extraction and metadata checks
1. Paste comments with 1편 - 2900년 7월 56일, 2편 - 317시간 28분 01초, 3편 - 341/912/0, plus background text 시대적 배경은 3419년 1월 20일.
2. Expect 2900756, 3172801, 3419120. The episode number must not be appended. The background line should not create an extra candidate.
3. The editable candidate list should show each episode, evidence, current value and verification state: exists, 404/410 not found, or unavailable.
4. Edit a number, add manual rows, delete rows, select/unselect and reverify. Manual values must not be overwritten by asynchronous results.
5. Save selected candidates. Only distinct valid numbers are saved and reading records remain independent.

## Languages and banner
6. Switching languages always displays the fixed native names 한국어 / English / 日本語.
7. The sidebar library total and offline stored count should be translated into English and Japanese.
8. Home banner art source: Default, Upload, Random Library Cover. Random uses real locally cached cover images; a manual shuffle chooses another. Missing covers fall back to the default.
9. Uploading a custom picture activates custom mode; switching the banner mode does not delete artwork.
10. Install over v0.1.8 on Windows and Android; verify persisted library JSON, CBZ, favorites and reader settings.

## Limitations
- Existence alone does not prove an ID is the intended work. The user decides which candidates to save.
- Verifier does not download images; at most 3 concurrent metadata checks and up to 24 IDs per batch.
- Built-in cover designs are decorative presets without image files and cannot be selected as random bitmap backgrounds.