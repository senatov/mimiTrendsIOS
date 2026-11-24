import plistlib
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from finalize_installer_window import main, plist_blobs


class InstallerWindowTests(unittest.TestCase):
    def test_hides_tab_bar_without_changing_background(self):
        window = {
            "ShowToolbar": False,
            "ShowStatusBar": False,
            "ShowTabView": True,
            "ShowSidebar": False,
        }
        icons = {
            "backgroundType": 2,
            "backgroundImageAlias": b"/.background/background.png",
        }
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / ".DS_Store"
            path.write_bytes(
                b"Finder settings\0"
                + plistlib.dumps(window, fmt=plistlib.FMT_BINARY)
                + b"icon settings\0"
                + plistlib.dumps(icons, fmt=plistlib.FMT_BINARY)
            )
            original_size = path.stat().st_size
            main(path)
            values = [value for _, _, _, value in plist_blobs(path.read_bytes())]
            self.assertEqual(path.stat().st_size, original_size)
            self.assertFalse(values[0]["ShowTabView"])
            self.assertEqual(values[1], icons)

    def test_rejects_missing_installer_background(self):
        window = {
            "ShowToolbar": False,
            "ShowStatusBar": False,
            "ShowTabView": True,
            "ShowSidebar": False,
        }
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / ".DS_Store"
            path.write_bytes(
                plistlib.dumps(window, fmt=plistlib.FMT_BINARY)
                + plistlib.dumps({"backgroundType": 0}, fmt=plistlib.FMT_BINARY)
            )
            with self.assertRaisesRegex(ValueError, "background"):
                main(path)


if __name__ == "__main__":
    unittest.main()
