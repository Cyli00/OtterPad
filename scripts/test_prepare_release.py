"""校验发布说明生成器的双语结构，不访问网络。"""
import os
import re
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
NOTES = ROOT / "build" / "release-preview" / "notes.md"


def pubspec_version() -> str:
    text = (ROOT / "pubspec.yaml").read_text(encoding="utf-8")
    match = re.search(r"^version:\s*(\d+\.\d+\.\d+)", text, re.M)
    if match is None:
        raise AssertionError("pubspec.yaml 缺少版本号")
    return match.group(1)


def bash_executable() -> str:
    # windows-2022 上 PATH 里的 bash 可能是 System32 的 WSL 启动器，直接退出 1。
    # 发布检查用的是 Git Bash。
    if os.name == "nt":
        candidate = Path(os.environ.get("ProgramFiles", r"C:\Program Files")) / "Git" / "bin" / "bash.exe"
        if candidate.is_file():
            return str(candidate)
    return "bash"


class PrepareReleaseTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.version = pubspec_version()
        # 发布工作流检出的就是这个 tag，构建号和上一个版本比较。
        result = subprocess.run(
            [bash_executable(), "scripts/prepare_release.sh", f"v{cls.version}"],
            cwd=ROOT,
            text=True,
            capture_output=True,
        )
        if result.returncode != 0:
            raise AssertionError(
                f"prepare_release.sh v{cls.version} exited {result.returncode}\n"
                f"stdout:\n{result.stdout}\n"
                f"stderr:\n{result.stderr}"
            )
        cls.notes = NOTES.read_text(encoding="utf-8")

    def test_packages_precede_bilingual_changelog(self):
        en_packages = self.notes.index("## Install packages")
        en_changes = self.notes.index("## Changes")
        zh_changes = self.notes.index("## 更新内容")
        self.assertLess(en_packages, en_changes)
        self.assertLess(en_changes, zh_changes)
        self.assertNotIn("## 安装包", self.notes)
        self.assertEqual(self.notes.count("## Install packages"), 1)
        packages = self.notes[:en_changes]
        self.assertNotIn("大多数现代设备", packages)

    def test_current_version_links_and_both_languages(self):
        version = self.version
        packages = self.notes.split("## Changes", 1)[0]
        self.assertIn(
            f"https://github.com/Cyli00/OtterPad/releases/download/v{version}/"
            f"OtterPad-{version}-android-arm64-v8a.apk",
            packages,
        )
        self.assertIn("SHA256SUMS", packages)
        self.assertIn(f"compare/", packages)
        en, zh = self.notes.split("## 更新内容", 1)
        changes = en.split("## Changes", 1)[1]
        self.assertIn("Added Persian (فارسی) as a translation target.", changes)
        self.assertIn("Fixes #3", changes)
        self.assertNotIn("翻译目标语言新增波斯语", changes)
        self.assertIn("翻译目标语言新增波斯语（فارسی）", zh)
        self.assertIn("Fixes #3", zh)
        self.assertNotIn("as a translation target", zh)


if __name__ == "__main__":
    unittest.main()
