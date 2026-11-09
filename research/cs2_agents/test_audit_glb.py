import json
from pathlib import Path
import struct
import tempfile
import unittest
from audit_glb import inspect_glb, audit


def glb(doc):
    payload = json.dumps(doc).encode()
    payload += b' ' * (-len(payload) % 4)
    return struct.pack('<4sII', b'glTF', 2, 20 + len(payload)) + struct.pack('<II', len(payload), 0x4E4F534A) + payload


class AuditTests(unittest.TestCase):
    def inspect(self, raw):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'test.glb'
            path.write_bytes(raw)
            return inspect_glb(path)

    def test_inventory(self):
        result = self.inspect(glb({'nodes': [{'name': 'hip'}], 'skins': [{'joints': [0]}],
                                  'animations': [{'name': 'walk', 'channels': [{'target': {'node': 0}}]}]}))
        self.assertEqual(result['joints'], ['hip'])
        self.assertEqual(result['animations'][0]['targets'], ['hip'])

    def test_truncated(self):
        with self.assertRaises(ValueError):
            self.inspect(b'glTF')

    def test_wrong_length(self):
        with self.assertRaises(ValueError):
            self.inspect(glb({}) + b'bad')

    def test_external_resources(self):
        result = self.inspect(glb({'images': [{'uri': 'texture.png'}, {'uri': 'data:image/png;base64,AA'}]}))
        self.assertEqual(result['external_uris'], ['texture.png'])

    def test_missing(self):
        with tempfile.TemporaryDirectory() as directory:
            result = audit(directory)
        self.assertEqual(len(result['files']), 3)
        self.assertTrue(all(v['status'] == 'missing' for v in result['files'].values()))

    def test_mismatch(self):
        with tempfile.TemporaryDirectory() as directory:
            (Path(directory) / 'ct-sas.glb').write_bytes(glb({}))
            self.assertEqual(audit(directory)['files']['ct-sas.glb']['status'], 'manifest_mismatch')


if __name__ == '__main__':
    unittest.main()
