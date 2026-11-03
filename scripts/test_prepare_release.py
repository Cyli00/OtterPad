"""校验发布说明生成器的双语结构，不访问网络。"""
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
NOTES = ROOT / "build" / "release-preview" / "notes.md"


class PrepareReleaseTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        subprocess.run(
            ["bash", "scripts/prepare_release.sh", "v0.1.7"],
            cwd=ROOT,
            check=True,
            text=True,
            capture_output=True,
        )
        cls.notes = NOTES.read_text(encoding="utf-8")

    def test_packages_precede_bilingual_changelog(self):
        en_packages = self.notes.index("## Install packages")
        zh_packages = self.notes.index("## 安装包")
        en_changes = self.notes.index("## Changes")
        zh_changes = self.notes.index("## 更新内容")
        self.assertLess(en_packages, zh_packages)
        self.assertLess(zh_packages, en_changes)
        self.assertLess(en_changes, zh_changes)

    def test_current_version_links_and_both_languages(self):
        self.assertIn(
            "https://github.com/Cyli00/OtterPad/releases/download/v0.1.7/"
            "OtterPad-0.1.7-android-arm64-v8a.apk",
            self.notes,
        )
        self.assertIn(
            "https://github.com/Cyli00/OtterPad/compare/v0.1.6...v0.1.7",
            self.notes,
        )
        self.assertIn("SHA256SUMS", self.notes)
        en, zh = self.notes.split("## 更新内容", 1)
        self.assertIn("reduce-motion setting", en)
        self.assertNotIn("减少动态效果设置", en.split("## Changes", 1)[1])
        self.assertIn("减少动态效果设置", zh)
        self.assertNotIn("reduce-motion setting", zh)


if __name__ == "__main__":
    unittest.main()
