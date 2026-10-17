#!/usr/bin/env python3
"""Patch the generated Windows Flutter host to permit only one app instance.

The repository uses 'flutter create --platforms=windows' in CI and for release
builds. The patch is idempotent and always operates on that generated runner,
not on the installed application's private settings or library data.
"""
from pathlib import Path
import re

SOURCE = Path("windows/runner/main.cpp")
MARKER = "HYP_VIEWER_SINGLE_INSTANCE"

def main():
    original = SOURCE.read_text(encoding="utf-8")
    if MARKER in original:
        print("Windows single-instance launcher already configured.")
        return
    if "#include <windows.h>" not in original:
        raise RuntimeError("Expected the Flutter Windows Win32 runner.")
    entry = re.search(r"\bint\s+APIENTRY\s+wWinMain\s*\([^)]*\)\s*\{",
                      original, flags=re.S)
    if not entry:
        raise RuntimeError("Flutter Windows wWinMain entry point not found.")
    patch = r"""
  // HYP_VIEWER_SINGLE_INSTANCE: keep the Windows tray app a singleton.
  HANDLE hyp_instance_mutex =
      CreateMutexW(nullptr, FALSE, L"Local\\HYPViewerSingleton");
  if (hyp_instance_mutex != nullptr &&
      GetLastError() == ERROR_ALREADY_EXISTS) {
    HWND existing = FindWindowW(nullptr, L"hyp_viewer");
    if (existing == nullptr) existing = FindWindowW(nullptr, L"HYP Viewer");
    if (existing != nullptr) {
      ShowWindow(existing, SW_RESTORE);
      SetForegroundWindow(existing);
    }
    CloseHandle(hyp_instance_mutex);
    return EXIT_SUCCESS;
  }
"""
    updated = original[:entry.end()] + patch + original[entry.end():]
    SOURCE.write_text(updated, encoding="utf-8")
    print("Windows single-instance guard inserted into generated runner.")

if __name__ == "__main__":
    main()
