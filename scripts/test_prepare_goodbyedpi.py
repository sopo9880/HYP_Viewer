import hashlib
import io
import tempfile
import unittest
from pathlib import Path
from zipfile import ZipFile

from prepare_goodbyedpi import unpack_verified, TOOLS, LICENSES, BLACKLIST


class GoodbyeDPIPackagingTests(unittest.TestCase):
    def sample(self):
        out = io.BytesIO()
        with ZipFile(out, "w") as z:
            for name in TOOLS:
                z.writestr("goodbyedpi/x86_64/" + name, b"X" * 2048)
            for name in (*LICENSES, BLACKLIST):
                z.writestr("goodbyedpi/" + name, b"Apache license example")
        return out.getvalue()

    def test_verifies_sha_before_writing_and_packs_required_files(self):
        data = self.sample()
        with tempfile.TemporaryDirectory() as temp:
            target = Path(temp) / "release" / "tools"
            files = unpack_verified(data, target,
                expected_sha256=hashlib.sha256(data).hexdigest())
            self.assertEqual(len(files), len(TOOLS) + len(LICENSES) + 3)
            for name in (*TOOLS, *LICENSES, BLACKLIST,
                         "hyp_dpi_supervisor.ps1", "HYP_GOODBYEDPI_NOTICES.txt"):
                self.assertTrue((target / name).is_file())
            self.assertIn("Apache", (target / LICENSES[0]).read_text())
            self.assertIn("WinDivert", (target / "HYP_GOODBYEDPI_NOTICES.txt").read_text())

    def test_wrong_digest_refuses_modified_binary(self):
        with tempfile.TemporaryDirectory() as temp:
            target = Path(temp) / "tools"
            with self.assertRaisesRegex(ValueError, "SHA-256"):
                unpack_verified(self.sample(), target)
            self.assertFalse(target.exists())


if __name__ == "__main__":
    unittest.main()
