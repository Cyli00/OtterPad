"""检查 Git 待提交内容；只报告位置与规则，不输出敏感值。"""
from pathlib import PurePosixPath
import argparse
import re
import subprocess
import sys


def protected_path(name):
    path = PurePosixPath(name.replace(chr(92), '/'))
    base = path.name.lower()
    return (
        base in {'.env', '.npmrc', '.pypirc', '.netrc', 'credentials', 'auth.json'}
        or base.startswith(('.env.', 'id_rsa', 'secrets.'))
        or path.suffix.lower() in {'.pem', '.key', '.p12', '.pfx', '.jks', '.keystore'}
        or any(part in {'.ssh', '.gnupg'} for part in path.parts)
    )


RULES = {
    'private-key': re.compile(r'-----BEGIN (?:RSA |EC |DSA |OPENSSH |ENCRYPTED )?PRIVATE KEY-----'),
    'provider-token': re.compile(r'\b(?:sk-(?:proj-|ant-)?[A-Za-z0-9_-]{24,}|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|AKIA[A-Z0-9]{16}|AIza[A-Za-z0-9_-]{35}|tvly-[A-Za-z0-9_-]{24,})\b'),
    'jwt': re.compile(r'\beyJ[A-Za-z0-9_-]{15,}\.[A-Za-z0-9_-]{15,}\.[A-Za-z0-9_-]{15,}\b'),
    'url-password': re.compile(r'https?://[^\s/:@]+:[^\s/@]+@', re.I),
}
ASSIGNMENT = re.compile(
    r'''["']?(?:api[_-]?key|access[_-]?token|refresh[_-]?token|client[_-]?secret|secret[_-]?access[_-]?key|password)["']?\s*[:=]\s*["']([A-Za-z0-9_+/=-]{24,})["']''', re.I,
)


def scan_text(text):
    findings = []
    for number, line in enumerate(text.splitlines(), 1):
        for rule, pattern in RULES.items():
            if pattern.search(line):
                findings.append((number, rule))
        for match in ASSIGNMENT.finditer(line):
            value = match[1]
            if len(set(value)) >= 12 and re.search('[0-9]', value) and re.search('[a-zA-Z]', value):
                findings.append((number, 'credential-literal'))
    return findings


def git(*args):
    return subprocess.check_output(['git', *args], stderr=subprocess.DEVNULL)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--staged', action='store_true', help='检查索引，默认模式')
    mode.add_argument('--tracked', action='store_true', help='检查全部已跟踪的索引内容')
    args = parser.parse_args()
    paths = git('ls-files', '-z') if args.tracked else git('diff', '--cached', '--name-only', '--diff-filter=ACMR', '-z')
    paths = [name for name in paths.decode('utf-8').split(chr(0)) if name]
    failures = 0
    for name in paths:
        if protected_path(name):
            print(f'{name}: protected-file (content not read)')
            failures += 1
            continue
        data = git('show', f':{name}')
        if b'\x00' in data:
            continue
        try:
            text = data.decode('utf-8')
        except UnicodeDecodeError:
            continue
        for line, rule in scan_text(text):
            print(f'{name}:{line}: {rule} [REDACTED]')
            failures += 1
    print(f'Secret check: {len(paths)} files, {failures} findings')
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
