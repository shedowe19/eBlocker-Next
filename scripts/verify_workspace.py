#!/usr/bin/env python3
"""Offline structural checks; intentionally not a substitute for build/tests."""
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
NS = {'m': 'http://maven.apache.org/POM/4.0.0'}

def verify(root=ROOT):
    lock = json.loads((root / 'upstream.lock.json').read_text())
    paths = set()
    for component in lock['components']:
        path = component['path']
        assert path not in paths, f'duplicate component: {path}'
        paths.add(path)
        target = (root / path).resolve()
        assert target.is_relative_to(root.resolve()), f'path traversal: {path}'
        assert target.is_dir(), f'missing source: {path}'
        assert re.fullmatch('[0-9a-f]{40}', component['commit']), path
        assert component['license_files'], f'missing license inventory: {path}'
        for license_path in component['license_files']:
            assert (root / license_path).is_file(), license_path
    pending = [root / 'pom.xml']
    seen = set()
    while pending:
        pom = pending.pop()
        assert pom not in seen, f'repeated Maven module: {pom}'
        seen.add(pom)
        tree = ET.parse(pom)
        for module in tree.findall('m:modules/m:module', NS):
            path = (pom.parent / module.text / 'pom.xml').resolve()
            assert path.is_file(), f'missing Maven module: {path}'
            pending.append(path)
        parent = tree.find('m:parent', NS)
        if parent is not None and parent.findtext('m:artifactId', namespaces=NS) == 'eblocker-top':
            rel = parent.findtext('m:relativePath', namespaces=NS)
            assert rel and (pom.parent / rel).is_file(), f'nonlocal eBlocker parent: {pom}'
    return len(paths), len(seen)

if __name__ == '__main__':
    components, modules = verify()
    print(f'OK: {components} pinned components, {modules} Maven modules. Build/runtime not checked.')
