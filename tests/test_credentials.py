"""Regression checks for the deliberately limited source-secret detector.

Synthetic candidates are assembled at runtime, not stored access credentials.
"""
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('check_credentials', ROOT / 'scripts/check_credentials.py')
scanner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(scanner)

class CredentialPatternTests(unittest.TestCase):
    def test_token_families(self):
        for prefix in ('gh' + 'p_', 'gh' + 'o_', 'github' + '_pat_'):
            with self.subTest(prefix=prefix):
                self.assertTrue(scanner.contains_secret(prefix + 'x' * 32))
        self.assertTrue(scanner.contains_secret('AK' + 'IA' + 'A' * 16))

    def test_xml_escaped_token_is_not_missed(self):
        candidate = 'gh' + 'p_' + 'x' * 32
        self.assertTrue(scanner.contains_secret(''.join('&#%d;' % ord(c) for c in candidate)))

    def test_provider_and_tor_assignments(self):
        for key in ('username', 'password'):
            self.assertTrue(scanner.contains_secret('squidblacklist.org.' + key + '=synthetic'))
        self.assertTrue(scanner.contains_secret('HashedControlPassword ' + '16:' + 'A' * 58))

    def test_external_references_and_comments_are_allowed(self):
        for text in ('<password>${env.GITHUB_TOKEN}</password>',
                     '# squidblacklist.org.password=external',
                     'squidblacklist.org.password=',
                     '# HashedControlPassword must be provisioned locally'):
            with self.subTest(text=text):
                self.assertFalse(scanner.contains_secret(text))

if __name__ == '__main__':
    unittest.main()
