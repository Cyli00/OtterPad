"""仅使用合成值验证提交检查，不访问真实凭据。"""
import unittest
import subprocess
import sys
import tempfile
from pathlib import Path
from check_secrets import protected_path, scan_text


class SecretCheckTests(unittest.TestCase):
    def test_protected_files(self):
        for name in ['.env', 'config/.env.local', 'tests/auth.json', 'cert/server.key', 'id_rsa.pub']:
            self.assertTrue(protected_path(name), name)
        self.assertFalse(protected_path('lib/core/secure_credential_vault.dart'))

    def test_provider_tokens_and_credentials(self):
        values = ['sk-' + 'A1b2' * 12, 'ghp_' + 'x' * 36, 'AKIA' + 'X' * 16]
        for value in values:
            self.assertTrue(scan_text('token = ' + value))
        value = 'AbCdEfGhIjKlMnOp1234567890'
        self.assertTrue(scan_text('apiKey = "' + value + '"'))
        self.assertTrue(scan_text('https://' + 'sample:pass' + '@example.invalid'))

    def test_labels_storage_keys_and_secret_references_are_safe(self):
        text = '\n'.join([
            '"apiKey": "API Key"',
            'const _apiKeyKey = "doc_extract.mineru.api_key";',
            'TOKEN: ${{ secrets.RELEASE_TOKEN }}',
            'const apiKey = "";',
        ])
        self.assertEqual(scan_text(text), [])

    def test_report_does_not_contain_secret(self):
        value = 'sk-' + 'sample' * 8
        findings = scan_text(value)
        self.assertNotIn(value, str(findings))
        self.assertEqual(findings, [(1, 'provider-token')])

    def test_reads_staged_content_instead_of_worktree(self):
        script = Path(__file__).with_name('check_secrets.py').resolve()
        with tempfile.TemporaryDirectory() as directory:
            subprocess.run(['git', 'init', '-q', directory], check=True)
            file = Path(directory) / 'config.txt'
            value = 'sk-' + 'sample' * 8
            file.write_text(value)
            subprocess.run(['git', '-C', directory, 'add', 'config.txt'], check=True)
            file.write_text('safe working copy')
            result = subprocess.run([sys.executable, str(script)], cwd=directory, capture_output=True, text=True)
            self.assertEqual(result.returncode, 1)
            self.assertIn('config.txt:1: provider-token', result.stdout)
            self.assertNotIn(value, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
