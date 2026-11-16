import importlib.util
from pathlib import Path
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('verify_workspace', ROOT / 'scripts/verify_workspace.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class WorkspaceTests(unittest.TestCase):
    def test_structure_and_provenance(self):
        self.assertEqual(module.verify(ROOT), (22, 17))

    def test_legacy_dns_dependencies_are_local(self):
        import re
        gemfile = ROOT / 'legacy/dns/Gemfile'
        paths = re.findall(r":path => '([^']+)'", gemfile.read_text())
        self.assertEqual(len(paths), 3)
        self.assertRegex(gemfile.read_text(), r"gem\s+'async-io',\s*'=\s*1\.43\.2'")
        self.assertNotIn(':git =>', gemfile.read_text())
        for path in paths:
            target = (gemfile.parent / path).resolve()
            self.assertTrue(target.is_relative_to(ROOT))
            self.assertTrue(list(target.glob('*.gemspec')), str(target))

    def test_led_dependencies_are_local(self):
        import re
        gemfile = ROOT / 'services/led/Gemfile'
        paths = re.findall(r":path => '([^']+)'", gemfile.read_text())
        self.assertEqual(len(paths), 1)
        self.assertRegex(gemfile.read_text(), r"gem\s+'async-io',\s*'=\s*1\.43\.2'")
        self.assertNotIn(':git =>', gemfile.read_text())
        for path in paths:
            target = (gemfile.parent / path).resolve()
            self.assertTrue(target.is_relative_to(ROOT))
            self.assertTrue(list(target.glob('*.gemspec')), str(target))

    def test_documented_entrypoint(self):
        result = subprocess.run([sys.executable, str(ROOT / 'scripts/verify_workspace.py')], cwd='/tmp', capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('22 pinned components', result.stdout)

if __name__ == '__main__':
    unittest.main()
