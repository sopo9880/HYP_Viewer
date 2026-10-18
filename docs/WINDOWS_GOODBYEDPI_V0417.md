# Windows GoodbyeDPI integration (v0.4.17)

- Publisher: https://github.com/ValdikSS/GoodbyeDPI
- Pinned ZIP: 0.2.3rc3-2, SHA-256:
  37f96b32d050dadcc930a639eba68e1ccd57ed5c04a5f77dfca908f01905a4c5
- The Windows installer includes the original x86_64 executable, WinDivert
  DLL/driver, Russian blacklist and all third-party license texts.
- Only user-enabled mode starts the engine; auto-start requires a separate
  opt-in. Windows UAC consent is mandatory and cannot be bypassed.
- The engine is supervised by an elevated PowerShell script, not installed
  as a permanent Windows service. The supervisor watches its owning HYP Viewer
  PID, and stops the engine when the app fully exits or sends a stop signal.
- Custom arguments are a STRICT safe whitelist (flags, small integer values,
  IPv4 DNS address and relative *.txt blacklist filename). They are
  not arbitrary shell commands. Unsupported flags are rejected.
- Presets with DNS redirection are opt-in and use the upstream documented
  77.88.8.8:1253 resolver; do not assume they are appropriate for Korea.
- WinDivert changes network behavior beyond HYP Viewer. Antivirus tools
  and Windows security policies may block it. The app reports failures and
  never attempts to disable protection.
- App library, saved settings and reading history are not modified by DPI.
- Russian blacklist is sourced from upstream, not Korea-specific. Use
  recommended or a reviewed custom mode unless deliberately opting in.

Running packaging tests:
  python -m unittest discover -s scripts -p test_prepare_goodbyedpi.py
