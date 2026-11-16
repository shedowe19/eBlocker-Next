import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class DebianInventoryTests(unittest.TestCase):
    def test_every_package_definition_is_covered(self):
        inventory = json.loads((ROOT / 'build/debian/packages.json').read_text())
        definitions = set()
        for path in ROOT.rglob('control'):
            relative = path.relative_to(ROOT)
            if any(part in ('target', 'node_modules', '.git') for part in relative.parts):
                continue
            name = relative.as_posix()
            if name.endswith('/debian/control') or '/deb/control/control' in name:
                definitions.add(name)
        self.assertEqual(definitions, set(inventory['definitions']))
        for recipe in inventory['external_recipes']:
            self.assertTrue((ROOT / recipe).is_file())
        names = sum(inventory['groups'].values(), [])
        self.assertEqual(len(names), len(set(names)))
        self.assertEqual(len(names), 15)
