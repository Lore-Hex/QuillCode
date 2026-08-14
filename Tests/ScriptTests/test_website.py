#!/usr/bin/env python3

from __future__ import annotations

from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
BUILD_SCRIPT = REPOSITORY_ROOT / "scripts/build-website.py"
VERIFY_SCRIPT = REPOSITORY_ROOT / "scripts/verify-website.py"


class WebsiteTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.site = Path(self.temporary_directory.name) / "site"
        subprocess.run(
            ["python3", str(BUILD_SCRIPT), "--output", str(self.site)],
            cwd=REPOSITORY_ROOT,
            check=True,
            capture_output=True,
            text=True,
        )

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def verify(self) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["python3", str(VERIFY_SCRIPT), "--site", str(self.site)],
            cwd=REPOSITORY_ROOT,
            capture_output=True,
            text=True,
        )

    def test_staged_site_passes_release_contract(self) -> None:
        result = self.verify()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Verified Quill Cowork website", result.stdout)
        self.assertTrue((self.site / "static/media/quill-cowork-desktop.png").is_file())

    def test_thin_installer_regression_fails(self) -> None:
        index = self.site / "index.html"
        index.write_text(
            index.read_text(encoding="utf-8").replace(
                "Quill-Cowork-macOS-universal.dmg",
                "Quill-Cowork-macOS-arm64.dmg",
                1,
            ),
            encoding="utf-8",
        )
        result = self.verify()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("universal installer links", result.stderr)

    def test_missing_local_asset_fails(self) -> None:
        shutil.rmtree(self.site / "static/fonts")
        result = self.verify()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("asset inventory drifted", result.stderr)

    def test_unvalidated_manifest_fetch_fails(self) -> None:
        script = self.site / "static/site.js"
        script.write_text(
            script.read_text(encoding="utf-8").replace("readCurrentRelease", "readRelease"),
            encoding="utf-8",
        )
        result = self.verify()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("fail-closed validated", result.stderr)

    def test_stable_feed_removal_fails(self) -> None:
        script = self.site / "static/site.js"
        script.write_text(
            script.read_text(encoding="utf-8").replace(
                "https://api.github.com/repos/Lore-Hex/QuillCode/releases/latest",
                "https://example.com/releases/latest",
            ),
            encoding="utf-8",
        )
        result = self.verify()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("prefer stable", result.stderr)


if __name__ == "__main__":
    unittest.main()
