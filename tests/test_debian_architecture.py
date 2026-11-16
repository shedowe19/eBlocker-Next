import importlib.util
import io
from pathlib import Path
import tarfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('verify_debian_packages', ROOT / 'build/debian/verify-packages.py')
verifier = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verifier)


def archive_with_elf(machine, byte_order=1, elf_class=2):
    header = bytearray(20)
    header[:4] = b'\x7fELF'
    header[4:6] = bytes([elf_class, byte_order])
    header[18:20] = machine.to_bytes(2, 'little' if byte_order == 1 else 'big')
    stream = io.BytesIO()
    with tarfile.open(fileobj=stream, mode='w') as archive:
        member = tarfile.TarInfo('opt/example/bin/program')
        member.size = len(header)
        archive.addfile(member, io.BytesIO(header))
        link = tarfile.TarInfo('opt/example/bin/link')
        link.type = tarfile.SYMTYPE
        link.linkname = '/outside/archive'
        archive.addfile(link)
    stream.seek(0)
    return stream


class DebianArchitectureTests(unittest.TestCase):
    def test_stream_checks_members_after_a_large_payload(self):
        stream = io.BytesIO()
        header = bytearray(20)
        header[:6] = b'\x7fELF\x02\x01'
        header[18:20] = (183).to_bytes(2, 'little')
        with tarfile.open(fileobj=stream, mode='w') as archive:
            for name in ('program', 'library.so'):
                payload = bytes(header) + b'\0' * 131072
                member = tarfile.TarInfo(name)
                member.size = len(payload)
                archive.addfile(member, io.BytesIO(payload))
        stream.seek(0)
        self.assertEqual(verifier.inspect_elf_stream(stream, 'arm64'), 2)

    def test_native_arm64_and_amd64_headers_are_accepted(self):
        self.assertEqual(verifier.inspect_elf_stream(archive_with_elf(183), 'arm64'), 1)
        self.assertEqual(verifier.inspect_elf_stream(archive_with_elf(62), 'amd64'), 1)

    def test_amd64_payload_cannot_be_mislabeled_arm64(self):
        with self.assertRaisesRegex(ValueError, 'Wrong ELF machine'):
            verifier.inspect_elf_stream(archive_with_elf(62), 'arm64')

    def test_32_bit_payload_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'non-64-bit'):
            verifier.inspect_elf_stream(archive_with_elf(40, elf_class=1), 'arm64')

    def test_big_endian_payload_is_not_debian_arm64(self):
        with self.assertRaisesRegex(ValueError, 'little-endian'):
            verifier.inspect_elf_stream(archive_with_elf(183, byte_order=2), 'arm64')
