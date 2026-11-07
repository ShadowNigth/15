#!/usr/bin/env python3
"""Fetch build inputs, not runtime dependencies, from the pinned upstream Git tree.
Requires gh authentication; never requests/stores credentials. Stdlib only.
"""
import argparse,base64,concurrent.futures,hashlib,json,subprocess
from pathlib import Path
PIN='1eb8067fd0b7214df5bccf3ac3807fbaa3aee70d'
REPO='zh667/ScCsgoKnives'
def api(path):return json.loads(subprocess.check_output(['gh','api',f'repos/{REPO}/'+path]))
def main():
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('directory',nargs='?',type=Path,default=Path.home()/'.cache/cs15-native-world-source');args=parser.parse_args()
 tree=api('git/trees/'+PIN+'?recursive=1');assert not tree.get('truncated')
 exact={'src/ScCsgoKnives/AnimationData/cs2_casings.json','src/ScCsgoTactical/Assets/Textures/ScCsgoTactical/defuser_item.png'}
 for role in ['ct','t']:
  exact.add(f'src/ScCsgoTactical/Assets/Animations/ScCsgoTactical/{role}.scanim')
 for name in ['ct','t','hostage','defuser_item']:
  exact.add(f'src/ScCsgoTactical/Assets/Models/ScCsgoTactical/{name}.glb')
 wanted=[r for r in tree['tree'] if r['type']=='blob' and (r['path'] in exact or r['path']=='src/ScCsgoKnives/Assets/Models/ScCsgoKnives/chicken.glb' or (r['path'].startswith('src/ScCsgoKnives/Assets/') and ('/casing_' in r['path'] and r['path'].endswith(('.obj','.png')) or '/hud_ammo_' in r['path'])))]
 def fetch(r):
  out=args.directory/r['path'];data=out.read_bytes() if out.exists() else None
  def git_hash(b):return hashlib.sha1(b'blob '+str(len(b)).encode()+b'\0'+b).hexdigest()
  if data is None or git_hash(data)!=r['sha']:data=base64.b64decode(api('git/blobs/'+r['sha'])['content'])
  assert git_hash(data)==r['sha'];out.parent.mkdir(parents=True,exist_ok=True);out.write_bytes(data);return r['path']
 with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
  for name in pool.map(fetch,wanted):print('VERIFIED',name)
 print('Pinned build inputs saved to',args.directory)
if __name__=='__main__':main()
