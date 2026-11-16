#!/usr/bin/env python3
"""Inspect built Debian archives without installing or running their scripts."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[2]


ELF_MACHINES = {'amd64': 62, 'arm64': 183}


def inspect_elf_stream(stream, target):
    """Read archive members without extracting or executing any package files."""
    count = 0
    with tarfile.open(fileobj=stream, mode='r|') as archive:
        for member in archive:
            if not member.isfile():
                continue
            with archive.extractfile(member) as source:
                header = source.read(20)
            if not header.startswith(b'\x7fELF'):
                continue
            if len(header) < 20 or header[4] != 2 or header[5] != 1:
                raise ValueError(f'Invalid or non-64-bit little-endian ELF file: {member.name}')
            machine = int.from_bytes(header[18:20], 'little')
            if machine != ELF_MACHINES[target]:
                raise ValueError(f'Wrong ELF machine in {member.name}: {machine}; expected {target}')
            count += 1
    return count


def inspect_elf_package(package, target):
    with tempfile.TemporaryFile() as errors:
        process = subprocess.Popen(['dpkg-deb', '--fsys-tarfile', str(package)],
                                   stdout=subprocess.PIPE, stderr=errors)
        try:
            count = inspect_elf_stream(process.stdout, target)
            # Consume the tar padding so the producer can finish before wait().
            while process.stdout.read(65536):
                pass
            if process.wait() != 0:
                errors.seek(0)
                raise ValueError(f'Cannot inspect package {package}: {errors.read().decode(errors="replace")}')
            return count
        finally:
            process.stdout.close()
            if process.poll() is None:
                process.kill()
            process.wait()


def inspect(directory, group=None, target_arch=None):
    inventory = json.loads((ROOT / 'build/debian/packages.json').read_text())
    target_arch = target_arch or os.environ.get('TARGET_ARCH') or inventory['architecture']
    if target_arch not in inventory['architectures']:
        raise ValueError(f'Unsupported architecture: {target_arch}')
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
        if architecture not in (target_arch, 'all'):
            raise ValueError(f'Unexpected architecture for {name}: {architecture}')
        if not version or any(x in version for x in ('${', '[[', ']]')):
            raise ValueError(f'Unresolved package version for {name}: {version}')
        if name in found:
            raise ValueError(f'Duplicate package: {name}')
        listing = subprocess.check_output(['dpkg-deb', '--contents', str(package)], text=True)
        if not any(line.startswith(('-', 'l')) for line in listing.splitlines()):
            raise ValueError(f'Package has no files: {name}')
        elf_count = inspect_elf_package(package, target_arch)
        found.add(name)
        with package.open('rb') as stream:
            digest = hashlib.file_digest(stream, 'sha256').hexdigest()
        records.append({'file': package.name, 'package': name, 'version': version,
                        'architecture': architecture, 'bytes': package.stat().st_size,
                        'sha256': digest, 'elf_files': elf_count})
    missing = expected - found
    if missing:
        raise ValueError('Missing packages: ' + ', '.join(sorted(missing)))
    manifest = {'distribution': inventory['distribution'], 'architecture': target_arch,
                'commit': os.environ.get('GITHUB_SHA'), 'group': group or 'all', 'packages': records}
    (directory / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    (directory / 'SHA256SUMS').write_text(''.join(f"{p['sha256']}  {p['file']}\n" for p in records))
    print(f"OK: {len(expected)} required packages, {len(records)} inspected archives")
    return manifest


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    parser.add_argument('--group', choices=['java', 'services', 'ruby', 'squid', 'tor'])
    parser.add_argument('--architecture', choices=['amd64', 'arm64'])
    arguments = parser.parse_args()
    inspect(arguments.directory.resolve(), arguments.group, arguments.architecture)
