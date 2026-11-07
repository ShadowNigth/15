#!/usr/bin/env python3
"""Fetch the exact 42 native JSON files used by the conversion (gh, stdlib only).

The files are build inputs, not required to open/play the editable Godot project.
Defaults outside the repository so downloaded inputs cannot enter a source ZIP.
"""
import argparse
import base64
import concurrent.futures
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
UPSTREAM = 'zh667/ScCsgoKnives'
PIN = '1eb8067fd0b7214df5bccf3ac3807fbaa3aee70d'


def api(path):
    return json.loads(subprocess.check_output(['gh','api',f'repos/{UPSTREAM}/'+path]))


def git_hash(raw):
    return hashlib.sha1(b'blob '+str(len(raw)).encode()+b'\0'+raw).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory',nargs='?',type=Path,default=Path.home()/'.cache/cs15-native-guns')
    args = parser.parse_args()
    args.directory.mkdir(parents=True,exist_ok=True)
    report = json.loads((ROOT/'data/native_gun_animation_report.json').read_text())
    wanted = {entry['source_weapon']+'.cs2.animation.json' for entry in report.values()}
    tree = api('git/trees/'+PIN+'?recursive=1')
    assert not tree.get('truncated'), 'Upstream tree must be complete'
    files = [entry for entry in tree['tree'] if Path(entry['path']).name in wanted]
    assert len(files)==42 and len({Path(entry['path']).name for entry in files})==42
    hashes = {entry['source_weapon']:entry['animation_sha256'] for entry in report.values()}

    def fetch(entry):
        name = Path(entry['path']).name
        path = args.directory/name
        raw = path.read_bytes() if path.exists() else None
        if raw is None or git_hash(raw) != entry['sha']:
            raw = base64.b64decode(api('git/blobs/'+entry['sha'])['content'])
        assert git_hash(raw)==entry['sha'],name+' Git blob hash mismatch'
        assert hashlib.sha256(raw).hexdigest()==hashes[name.removesuffix('.cs2.animation.json')],name+' provenance mismatch'
        path.write_bytes(raw)
        return name

    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        for name in pool.map(fetch,files): print('VERIFIED',name,flush=True)
    print('42 pinned source files verified in',args.directory)


if __name__=='__main__':
    main()
