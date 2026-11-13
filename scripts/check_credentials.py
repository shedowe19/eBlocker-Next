#!/usr/bin/env python3
"""Check every reachable Git blob for common access-token and XML secret forms.
Not a complete secret detector. Intentional upstream test key fixtures are retained.
Print paths/object IDs only, never credential values.
"""
import html
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
PATTERNS = [r'(?m)^\s*HashedControlPassword\s+16:', r'(?m)^\s*squidblacklist\.org\.(?:username|password)\s*=\s*\S+', r'gh[pousr]_[A-Za-z0-9]{20,}', r'github_pat_[A-Za-z0-9_]{20,}', r'AKIA[A-Z0-9]{16}', r'<password>(?!\$\{|&lt;)[A-Za-z0-9_#]{16,}</password>']
def contains_secret(text):
    text = html.unescape(text)
    return any(re.search(pattern, text) for pattern in PATTERNS)

def main():
    objects = subprocess.check_output(['git', 'rev-list', '--objects', '--all'], cwd=ROOT, text=True)
    failures = []
    entries = dict(line.partition(' ')[::2] for line in objects.splitlines())
    batch = subprocess.run(['git', 'cat-file', '--batch'], cwd=ROOT,
                           input=('\n'.join(entries) + '\n').encode(), capture_output=True, check=True)
    import io
    stream = io.BytesIO(batch.stdout)
    for _ in entries:
        oid, kind, size = stream.readline().decode().strip().split()
        data = stream.read(int(size)); stream.read(1)
        if kind == 'blob' and contains_secret(data.decode('utf-8', errors='replace')):
            failures.append(f'{oid} {entries[oid]}')
    if failures:
        print('Potential credentials in history:\n' + '\n'.join(failures))
        return 1
    print('No known access-token patterns found in reachable Git history (not exhaustive).')
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
