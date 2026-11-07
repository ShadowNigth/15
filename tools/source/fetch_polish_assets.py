"""Fetch pinned upstream PNGs through authenticated GitHub API; no runtime downloads."""
import base64, concurrent.futures, hashlib, json, subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def api(path):return json.loads(subprocess.check_output(['gh','api',path]))
def main():
 manifest=ROOT/'data/polish_assets.json'
 pin=json.loads(manifest.read_text())['tree'] if manifest.exists() else 'main'
 tree=api('repos/zh667/ScCsgoKnives/git/trees/'+pin+'?recursive=1');prefix='src/ScCsgoKnives/Assets/Textures/ScCsgoKnives/'
 fx={'hud_armor.png','hud_helmet.png','muzzle_fire.png','muzzle_smoke.png','grenade_blast_atlas.png','grenade_fireburst_atlas.png','grenade_smoke_atlas.png','grenade_glow.png'}
 selected=[n for n in tree['tree'] if n['path'].startswith(prefix) and (n['path'][len(prefix):] in fx or n['path'][len(prefix):].startswith('hud_weapon_') or (n['path'][len(prefix):].startswith('grenade_') and n['path'].endswith('_slot.png')))]
 def fetch(n):
  data=base64.b64decode(api('repos/zh667/ScCsgoKnives/git/blobs/'+n['sha'])['content']);name=n['path'].split('/')[-1];target=ROOT/'assets'/'polish'/name;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(data)
  return {'source':n['path'],'git_blob':n['sha'],'target':str(target.relative_to(ROOT)),'sha256':hashlib.sha256(data).hexdigest()}
 with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:entries=list(pool.map(fetch,selected))
 (ROOT/'data/polish_assets.json').write_text(json.dumps({'repository':'zh667/ScCsgoKnives','tree':tree['sha'],'assets':entries},indent=2)+'\n');print('Fetched',len(entries),'pinned assets')
if __name__=='__main__':main()
