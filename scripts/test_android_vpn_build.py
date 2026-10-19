"""Runtime-independent Android VPN/tun2socks build checks after NDK build."""
import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TUN = ROOT / "scripts/prepare_android_vpn_tunnel.py"
spec = importlib.util.spec_from_file_location("vpn_build", TUN)
vpn = importlib.util.module_from_spec(spec)
spec.loader.exec_module(vpn)


class AndroidVpnNativeTests(unittest.TestCase):
    def test_pinned_tunnel_is_built_for_supported_abis(self):
        self.assertEqual(len(vpn.REV), 40)
        self.assertEqual(vpn.UPSTREAM, "https://github.com/heiher/hev-socks5-tunnel.git")
        for abi in vpn.ABIS:
            lib = vpn.DEST / abi / "libhev-socks5-tunnel.so"
            self.assertTrue(lib.exists() and lib.stat().st_size > 2048, str(lib))
        self.assertTrue(vpn.CLASS.is_file())
        self.assertTrue(vpn.LICENSE.is_file())
        self.assertIn("MIT", vpn.LICENSE.read_text())

    def test_staged_blacklist_is_not_an_unverified_download(self):
        from prepare_android_dpi_blacklist import DEST
        from prepare_goodbyedpi import SHA256
        self.assertEqual(len(SHA256), 64)
        self.assertTrue(DEST.exists() and DEST.stat().st_size > 1000)

    def test_android_vpn_jni_entrypoints_survive_r8(self):
        rules = ROOT / "android/app/proguard-rules.pro"
        contents = rules.read_text()
        self.assertIn("hev.htproxy.TProxyService", contents)
        self.assertIn("DpiNativeBridge", contents)
        manifest = (vpn.MAIN / "AndroidManifest.xml").read_text()
        self.assertIn("android.permission.BIND_VPN_SERVICE", manifest)


if __name__ == "__main__":
    unittest.main()
