"""Calibrate existing held-weapon coordinates onto native animated right hands.
Does not change any weapon geometry or the original character GLBs.
"""
import json,hashlib
from pathlib import Path
import numpy as np
from .glb_read import load
from .add_cs2_knives import original_pose
ROOT=Path(__file__).resolve().parents[2]
def main():
 report=json.loads((ROOT/'data/native_gun_animation_report.json').read_text()); weapons=json.loads((ROOT/'data/weapons.json').read_text())['weapons'];out={}
 for role,classic in [('ct','urban'),('t','terror')]:
  d,b=load(ROOT/f'assets/models/native/{role}.glb');c,cb=load(ROOT/f'assets/models/players/{classic}.glb');hand=next(i for i,n in enumerate(d['nodes']) if n.get('name')=='hand_R');ch=next(i for i,n in enumerate(c['nodes']) if n.get('name')=='Bip01 R Hand');clips={a['name'] for a in d['animations']};out[role]={}
  for wid in weapons:
   source=report.get(wid,{}).get('source_weapon', 'default_'+role);hold='hold_'+source
   if hold not in clips:hold='hold_default_'+role if wid=='knife' else 'hold_ak47'
   ext='onehanded' if weapons[wid].get('slot')==2 else 'knife' if wid=='knife' else 'carbine'
   ca='ref_aim_'+ext
   n=original_pose(d,b,hold)[hand];old=original_pose(c,cb,ca)[ch]
   rotate=np.diag([-1.,1.,-1.]);basis=np.linalg.inv(n[:3,:3])@rotate@old[:3,:3];pelvis=next(i for i,n in enumerate(d['nodes']) if n.get('name')=='pelvis')
   out[role][wid]={'hold':hold,'basis':basis.round(8).tolist(),'pelvis_basis':original_pose(d,b,hold)[pelvis][:3,:3].round(8).tolist(),'classic_basis':old[:3,:3].round(8).tolist()}
 (ROOT/'data/native_actor_sockets.json').write_text(json.dumps(out,indent=2)+'\n')
if __name__=='__main__':main()
