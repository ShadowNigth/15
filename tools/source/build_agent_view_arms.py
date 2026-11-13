"""Build cosmetic canonical arm/glove meshes; preserve original UVs, no paint reprojection.
Runtime remaps canonical bind coordinates to each weapon's existing skeleton.
"""
import copy,json,hashlib,io
from pathlib import Path
import numpy as np
from PIL import Image
from .expand_cs2go_cosmetics import decode,ROOT,glove_bone
from .import_modern_agents import read_glb,write_glb
from .build_sport_gloves import _accessor
from .smd_converter import GlbWriter
OUT=ROOT/'assets/models/agent_arms'
SOURCES={'sas':'gloves/agents/5600','phoenix':'gloves/agents/5200','st6':'gloves/agents/5401','dragomir':'gloves/agents/5500','sas_officer':'gloves/agents/5601','fbi':'gloves/agents/5308','leet':'gloves/agents/5105','phoenix_a':'gloves/agents/5200'}

def native(name):
    # Twist helpers are not the forearm: merging them moves the cuff in poses.
    if name.endswith('_ForeTwist'):return 'arm_twist_'+('L' if '_L_' in name else 'R')
    result=glove_bone(name)
    if result:return result
    if 'UpperArm' in name:return 'arm_upper_'+('L' if '_L_' in name else 'R')
    return ''

def frame(doc,blob,skin):
    s=doc['skins'][skin];inv=_accessor(doc,blob,s['inverseBindMatrices']).reshape(-1,4,4).transpose(0,2,1)
    return {doc['nodes'][n]['name']:np.linalg.inv(m.astype(float)) for n,m in zip(s['joints'],inv)}

def axis_between(a,b):
    # Infer local coordinate conventions from the same hand/finger bone chains.
    aa=[];bb=[]
    for side in ['L','R']:
      for finger in ['thumb','index','middle','ring','pinky']:
       for i in [1,2]:
        n=f'finger_{finger}_{i}_{side}';p=f'finger_{finger}_{i-1}_{side}'
        if all(n in x and p in x for x in [a,b]):
         av=(np.linalg.inv(a[p])@a[n])[:3,3];bv=(np.linalg.inv(b[p])@b[n])[:3,3]
         if min(np.linalg.norm(av),np.linalg.norm(bv))>1e-6:aa.append(av/np.linalg.norm(av));bb.append(bv/np.linalg.norm(bv))
    if not aa:raise ValueError('Missing common finger calibration')
    u,_,vt=np.linalg.svd(np.array(aa).T@np.array(bb));r=(u@vt).T
    if np.linalg.det(r)<0:u[:,-1]*=-1;r=(u@vt).T
    m=np.eye(4);m[:3,:3]=r
    return m

def target_frames(doc,blob):
    f=frame(doc,blob,0)
    return {native(n):v for n,v in f.items() if native(n)}

def build(avatar,path,td,tb,glove_prefix=""):
    is_glove = avatar == "sport" or bool(glove_prefix)
    if not path.startswith('gloves/'):
        raise ValueError('Only dedicated first-person packages are allowed: '+path)
    sd,sb=read_glb(decode('models/'+path+'.glb'))
    selected=[n for n in sd['nodes'] if 'mesh' in n and (('viewmodel' in n.get('name','')) if is_glove else n.get('name','').startswith(('agent_sleeves_','agent_hands_')))]
    if not selected:raise ValueError('Missing intended arms '+avatar)
    target_skin=td['skins'][0];target_nodes=target_skin['joints'];target_names=[td['nodes'][i]['name'] for i in target_nodes]
    target_by_native={native(name):i for i,name in enumerate(target_names) if native(name)}
    tf=target_frames(td,tb);writer=GlbWriter();primitives=[];materials=[];images=[];textures=[];stats=[]
    for node in selected:
      skin=sd['skins'][node['skin']];sf=frame(sd,sb,node['skin']);axes={}
      for side in ['L','R']:
        axes[side]=axis_between({n:m for n,m in sf.items() if n.endswith('_'+side)},{n:m for n,m in tf.items() if n.endswith('_'+side)})
        axes[side][:3,:3]*=1/0.8128
      for p in sd['meshes'][node['mesh']]['primitives']:
        mat=sd['materials'][p['material']];name=mat.get('name','')
        if is_glove and not name.startswith(glove_prefix or 'glove_sporty_'):continue
        forearm_only=node.get('name','').startswith('agent_hands_')
        if forearm_only and (not name.startswith('bare_arm') or avatar not in {'leet','phoenix','phoenix_a'}):continue
        a=p['attributes'];v=_accessor(sd,sb,a['POSITION']);norm=_accessor(sd,sb,a['NORMAL']);uv=_accessor(sd,sb,a['TEXCOORD_0']);j=_accessor(sd,sb,a['JOINTS_0']);w=_accessor(sd,sb,a['WEIGHTS_0']);faces=_accessor(sd,sb,p['indices']).reshape(-1,3)
        bone_names=[sd['nodes'][n]['name'] for n in skin['joints']]
        if forearm_only:
          # Dedicated first-person packages sometimes put exposed forearms in
          # their hands meshgroup. Retain only arm-weighted triangles, never
          # its default hands/gloves: Arsenal's selected glove stays independent.
          arm_weight=np.zeros(len(v))
          for k in range(4):
            arm_weight+=w[:,k]*np.array([bone_names[int(x)].startswith(('arm_upper_','arm_lower_')) for x in j[:,k]])
          faces=faces[arm_weight[faces].min(1)>.5]
        if len(faces)==0:continue
        ids,indices=np.unique(faces,return_inverse=True);v=v[ids];norm=norm[ids];uv=uv[ids];j=j[ids];w=w[ids]
        result=np.zeros_like(v);rn=np.zeros_like(norm);rj=np.zeros_like(j,dtype=np.uint16);rw=np.zeros_like(w)
        for col in range(4):
          for bind in np.unique(j[:,col]):
            mask=(j[:,col]==bind)&(w[:,col]>1e-7)
            if not mask.any():continue
            bn=bone_names[int(bind)];mapped=bn
            if mapped not in target_by_native:
              side='L' if '_L' in mapped else 'R'
              mapped=('arm_lower_'+side) if ('arm_' in mapped or 'clavicle' in mapped) else ('hand_'+side)
            if mapped not in target_by_native:raise ValueError((avatar,bn,mapped))
            # Collapsed helper/upper-arm uses its surviving ancestor's frame.
            ref=mapped if mapped in sf else bn
            axis=axes['L' if mapped.endswith('_L') else 'R'];x=tf[mapped]@axis@np.linalg.inv(sf[ref]);points=np.c_[v[mask],np.ones(mask.sum())]
            result[mask]+=(points@x.T)[:,:3]*w[mask,col,None]
            rn[mask]+=(norm[mask]@np.linalg.inv(x[:3,:3]))*w[mask,col,None]
            rj[mask,col]=target_by_native[mapped];rw[mask,col]=w[mask,col]
        if not is_glove:
          # Keep the sleeve/skin endpoint behind the glove's wrist plane.
          # Compress only the last 8 cm, retaining UVs and anatomical weights.
          dominant=np.argmax(rw,axis=1)
          sides=np.array(['L' if '_L_' in target_names[int(rj[i,k])] else 'R' for i,k in enumerate(dominant)])
          for side in ['L','R']:
            mask=sides==side
            if not mask.any():continue
            wrist=tf['hand_'+side][:3,3];elbow=tf['arm_lower_'+side][:3,3]
            direction=wrist-elbow;direction/=np.linalg.norm(direction)
            u=(result[mask]-wrist)@direction
            if u.max()>-.008:
              scale=.072/(u.max()+.08)
              end=np.maximum(u+.08,0)
              result[mask]-=end[:,None]*(1-scale)*direction
        rn/=np.maximum(np.linalg.norm(rn,axis=1,keepdims=True),1e-8)
        # Keep the native texture transforms and repeat UVs; no resampling atlas.
        tex=mat.get('pbrMetallicRoughness',{}).get('baseColorTexture',{})
        transform=tex.get('extensions',{}).get('KHR_texture_transform',{})
        uv=uv*np.array(transform.get('scale',[1,1]))+np.array(transform.get('offset',[0,0]))
        material={'name':name,'doubleSided':True,'pbrMetallicRoughness':{'metallicFactor':0,'roughnessFactor':.85,'baseColorFactor':mat.get('pbrMetallicRoughness',{}).get('baseColorFactor',[1,1,1,1])[:3]+[1]}}
        if 'index' in tex:
          texture=sd['textures'][tex['index']];image_id=texture.get('source',texture.get('extensions',{}).get('EXT_texture_webp',{}).get('source'));image=sd['images'][image_id];view=sd['bufferViews'][image['bufferView']];raw=sb[view.get('byteOffset',0):view.get('byteOffset',0)+view['byteLength']]
          im=Image.open(io.BytesIO(raw));im.thumbnail((1024,1024));out=io.BytesIO();im.save(out,format='PNG')
          images.append({'bufferView':writer.view(out.getvalue()),'mimeType':'image/png'});textures.append({'source':len(images)-1});material['pbrMetallicRoughness']['baseColorTexture']={'index':len(textures)-1}
        if 'normalTexture' in mat:
          t=sd['textures'][mat['normalTexture']['index']];image_id=t.get('source',t.get('extensions',{}).get('EXT_texture_webp',{}).get('source'));image=sd['images'][image_id];view=sd['bufferViews'][image['bufferView']]
          im=Image.open(io.BytesIO(sb[view.get('byteOffset',0):view.get('byteOffset',0)+view['byteLength']])).convert('RGB');im.thumbnail((1024,1024));pixels=np.array(im).astype(float)
          if mat.get('extras',{}).get('roughnessChannel')=='normal.b':
            xy=pixels[:,:,:2]/127.5-1;pixels[:,:,2]=(np.sqrt(np.maximum(0,1-(xy*xy).sum(2)))*.5+.5)*255
          out=io.BytesIO();Image.fromarray(pixels.astype('uint8')).save(out,format='PNG');images.append({'bufferView':writer.view(out.getvalue()),'mimeType':'image/png'});textures.append({'source':len(images)-1});material['normalTexture']={'index':len(textures)-1}
        materials.append(material)
        attrs={n:writer.acc(arr,ctype,typ,34962,n=='POSITION') for n,arr,ctype,typ in [('POSITION',result.astype('<f4'),5126,'VEC3'),('NORMAL',rn.astype('<f4'),5126,'VEC3'),('TEXCOORD_0',uv.astype('<f4'),5126,'VEC2'),('JOINTS_0',rj.astype('<u2'),5123,'VEC4'),('WEIGHTS_0',rw.astype('<f4'),5126,'VEC4')]}
        primitives.append({'attributes':attrs,'indices':writer.acc(indices.astype('<u4').reshape(-1,1),5125,'SCALAR',34963),'material':len(materials)-1});stats.append({'material':name,'vertices':len(result),'triangles':len(indices)//3})
    if not primitives:raise ValueError('Empty arm conversion '+avatar)
    nodes=copy.deepcopy(td['nodes'])
    for n in nodes:n.pop('mesh',None);n.pop('skin',None)
    armature=next(i for i,n in enumerate(nodes) if n.get('name')=='Armature')
    nodes.append({'name':'AgentArms_'+avatar,'mesh':0,'skin':0});nodes[armature].setdefault('children',[]).append(len(nodes)-1)
    tglobal=frame(td,tb,0);ib=np.array([np.linalg.inv(tglobal[name]).T for name in target_names],dtype='<f4')
    output={'asset':{'version':'2.0','generator':'Canonical agent arms, original native UVs'},'scene':0,'scenes':[{'nodes':[0]}],'nodes':nodes,'meshes':[{'primitives':primitives}],'materials':materials,'images':images,'textures':textures,'skins':[dict(target_skin,inverseBindMatrices=writer.acc(ib.reshape(-1,16),5126,'MAT4'))],'bufferViews':writer.views,'accessors':writer.accessors}
    file=OUT/(avatar+'.glb');write_glb(file,output,writer.bin)
    return {'model':'res://assets/models/agent_arms/'+file.name,'source':'models/'+path+'.glb','extracted_from_body':False,'dedicated_first_person':True,'visual_substitute':avatar in {'fbi','leet','phoenix_a'},'surfaces':stats,'sha256':hashlib.sha256(file.read_bytes()).hexdigest(),'uv_sha256':hashlib.sha256(b''.join(_accessor(output,writer.bin,q['attributes']['TEXCOORD_0']).tobytes() for q in primitives)).hexdigest()}

def main():
    OUT.mkdir(parents=True,exist_ok=True);td,tb=read_glb(ROOT/'assets/models/weapons/v_ak47.glb')
    report={'source':'https://github.com/3kh0/cs2go','commit':'fb970df0ee8175d9b212d310f6a928f9f61014f2','agents':{},'targets':{}}
    for avatar,path in SOURCES.items():report['agents'][avatar]=build(avatar,path,td,tb);print('BUILT',avatar,flush=True)
    cf=target_frames(td,tb);canonical=frame(td,tb,0)
    for model in json.loads((ROOT/'data/sport_gloves.json').read_text())['models']:
      d,b=read_glb(ROOT/f'assets/models/weapons/{model}.glb');tf=target_frames(d,b);axes={side:axis_between({n:m for n,m in cf.items() if n.endswith('_'+side)},{n:m for n,m in tf.items() if n.endswith('_'+side)}) for side in ['L','R']}
      names={native(n):n for n in frame(d,b,0) if native(n)};xforms={};binds={}
      for name,matrix in canonical.items():
        nn=native(name)
        if not nn:continue
        reference=matrix
        if nn not in tf:
          if not nn.startswith('arm_upper_'):continue
          # Knife skins omit upper-arm binds. Collapse to the animated forearm,
          # preserving each vertex's offset relative to that canonical forearm.
          nn='arm_lower_'+nn[-1]
          reference=cf[nn]
        axis=axes['L' if nn.endswith('_L') else 'R'];x=tf[nn]@axis@np.linalg.inv(reference)
        xforms[name]={'target':names[nn],'matrix':x[:3,:].reshape(-1).tolist(),'bind':np.linalg.inv(tf[nn])[:3,:].reshape(-1).tolist()}
      report['targets'][model]=xforms
    (ROOT/'data/agent_view_arms.json').write_text(json.dumps(report,separators=(',',':'))+'\n')
if __name__=='__main__':main()
