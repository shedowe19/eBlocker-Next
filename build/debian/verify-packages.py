#!/usr/bin/env python3
"""Inspect built Debian archives without installing or running their scripts."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def inspect(directory, group=None):
    inventory = json.loads((ROOT / 'build/debian/packages.json').read_text())
    groups = inventory['groups']
    expected = set(groups[group] if group else sum(groups.values(), []))
    records = []
    found = set()
    for package in sorted(directory.glob('*.deb')):
        fields = subprocess.check_output([
            'dpkg-deb', '--show', '--showformat=${Package}\t${Version}\t${Architecture}\n',
            str(package)], text=True).strip().split('\t')
        if len(fields) != 3:
            raise ValueError(f'Invalid package metadata: {package}')
        name, version, architecture = fields
        base_name = name.removesuffix('-dbgsym')
        if name not in expected and base_name not in expected:
            raise ValueError(f'Unexpected package: {name}')
        if architecture not in (inventory['architecture'], 'all'):
            raise ValueError(f'Unexpected architecture for {name}: {architecture}')
        if not version or any(x in version for x in ('${', '[[', ']]')):
            raise ValueError(f'Unresolved package version for {name}: {version}')
        if name in found:
            raise ValueError(f'Duplicate package: {name}')
        listing = subprocess.check_output(['dpkg-deb', '--contents', str(package)], text=True)
        if not any(line.startswith(('-', 'l')) for line in listing.splitlines()):
            raise ValueError(f'Package has no files: {name}')
        found.add(name)
        with package.open('rb') as stream:
            digest = hashlib.file_digest(stream, 'sha256').hexdigest()
        records.append({'file': package.name, 'package': name, 'version': version,
                        'architecture': architecture, 'bytes': package.stat().st_size,
                        'sha256': digest})
    missing = expected - found
    if missing:
        raise ValueError('Missing packages: ' + ', '.join(sorted(missing)))
    manifest = {'distribution': inventory['distribution'], 'architecture': inventory['architecture'],
                'commit': os.environ.get('GITHUB_SHA'), 'group': group or 'all', 'packages': records}
    (directory / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    (directory / 'SHA256SUMS').write_text(''.join(f"{p['sha256']}  {p['file']}\n" for p in records))
    print(f"OK: {len(expected)} required packages, {len(records)} inspected archives")
    return manifest


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    parser.add_argument('--group', choices=['java', 'services', 'ruby', 'squid', 'tor'])
    arguments = parser.parse_args()
    inspect(arguments.directory.resolve(), arguments.group)
