#!/usr/bin/env python3
"""Install ALL pinned upstream audio, byte-exact, with Git/SHA256 provenance.

Requires authenticated gh; no Python dependencies. Original recordings are never
renamed over legacy files. Re-running verifies cached files before any download.
"""
import base64
import concurrent.futures
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
PIN = '1eb8067fd0b7214df5bccf3ac3807fbaa3aee70d'
REPO = 'zh667/ScCsgoKnives'


def api(path):
    return json.loads(subprocess.check_output(['gh', 'api', f'repos/{REPO}/{path}']))


def install():
    tree = api(f'git/trees/{PIN}?recursive=1')
    assert not tree.get('truncated')
    entries = [e for e in tree['tree'] if Path(e['path']).suffix.lower() in ('.ogg', '.wav', '.mp3', '.flac')]

    def fetch(e):
        # Module-relative paths preserve languages, teams and numbered variants.
        rel = e['path'].split('/Assets/Audio/', 1)[1].lower()
        dest = ROOT / 'assets/sounds/native' / rel
        raw = dest.read_bytes() if dest.exists() else b''
        def blob(data):
            return hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()
        if blob(raw) != e['sha']:
            raw = base64.b64decode(api('git/blobs/'+e['sha'])['content'])
        assert blob(raw) == e['sha'], e['path']
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(raw)
        return dict(source=e['path'], path='native/'+rel, git_blob=e['sha'], sha256=hashlib.sha256(raw).hexdigest(), bytes=len(raw))

    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        files = list(pool.map(fetch, entries))
    assert len({f['path'] for f in files}) == len(entries)
    manifest = dict(repository=REPO, commit=PIN, files=files)
    (ROOT/'data/native_audio_manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
    # Small authoritative timing/variant tables are conversion inputs, not binaries.
    cache = Path.home()/'.cache/scsounds-code'
    cache.mkdir(parents=True, exist_ok=True)
    for e in tree['tree']:
        if Path(e['path']).name in ('cs2_sounds.json', 'cs2_sound_variants.json'):
            (cache/Path(e['path']).name).write_bytes(base64.b64decode(api('git/blobs/'+e['sha'])['content']))
    print(f'VERIFIED {len(files)} original audio files, {sum(f["bytes"] for f in files)} bytes', flush=True)


if __name__ == '__main__':
    install()
