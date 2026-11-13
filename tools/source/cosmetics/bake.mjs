// Offline conversion only: fetched upstream baker/shaders live in .cache, never
// in the game. Runtime uses ordinary PNGs and needs no browser, GPU API or network.
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import {execFileSync} from 'node:child_process';
import {create, globals} from 'webgpu';
import {transform} from 'esbuild';
const root=path.resolve(process.argv[2]);
const work=path.resolve(root,'baker-runtime');fs.mkdirSync(work,{recursive:true});
const source=path.join(root,'apps/game/src');
let code=fs.readFileSync(path.join(source,'skin-baker.ts'),'utf8');
code=code.replace('import { assetFetch } from "./asset-url";',`import fs from 'node:fs';
const assetFetch=async url=>new Response(fs.readFileSync(${JSON.stringify(path.join(root,'packages/assets/public'))}+url));`);
code=code.replace('import { createLoadQueue } from "./loading";', 'const createLoadQueue=()=>async work=>work();');
code=code.replace('from "./skin-paint"','from "./skin-paint.mjs"');
for(const [name,text] of [['baker',code],['skin-paint',fs.readFileSync(path.join(source,'skin-paint.ts'),'utf8')]])
 fs.writeFileSync(path.join(work,name+'.mjs'),(await transform(text,{loader:'ts',format:'esm'})).code);
const swift=path.join(root,'swiftshader');fs.mkdirSync(swift,{recursive:true});
if(!fs.existsSync(path.join(swift,'libvulkan.so.1'))){
 const tar=path.join(root,'swiftshader.tar');
 const br=new URL('./node_modules/@sparticuz/chromium/bin/swiftshader.tar.br',import.meta.url);
 fs.writeFileSync(tar,zlib.brotliDecompressSync(fs.readFileSync(br)));
 execFileSync('tar',['xf',tar,'-C',swift]);
}
// The loader requires its library path at process launch; re-exec once.
if(!process.env.COSMETIC_GPU_READY){
 execFileSync(process.execPath,process.argv.slice(1),{stdio:'inherit',env:{...process.env,COSMETIC_GPU_READY:'1',LD_LIBRARY_PATH:swift,VK_ICD_FILENAMES:path.join(swift,'vk_swiftshader_icd.json')}});process.exit(0);
}
Object.assign(globalThis,globals);
Object.defineProperty(globalThis,'navigator',{value:{gpu:create(['backend=vulkan'])},configurable:true});
const {bakeSkin}=await import(path.join(work,'baker.mjs'));
for(const job of JSON.parse(fs.readFileSync(path.join(root,'bake-jobs.json')))){
 const output=path.join(root,'baked',job.id);fs.mkdirSync(output,{recursive:true});
 if(fs.existsSync(path.join(output,'manifest.json')))continue;
 const paint=JSON.parse(fs.readFileSync(path.join(root,'packages/assets/public',job.paint)));
 const result=await bakeSkin(paint,job.seed ?? 1,job.wear ?? 0.07);
 const manifest=[];
 for(let i=0;i<result.length;i++){
  const item=result[i],maps={};
  for(const [name,data] of Object.entries(item.maps)){
   const file=`${i}_${name}.rgba`;fs.writeFileSync(path.join(output,file),data);maps[name]=file;
  }
  manifest.push({material:item.material,maps,direct:item.direct});
 }
 fs.writeFileSync(path.join(output,'manifest.json'),JSON.stringify(manifest));console.log('BAKED',job.id);
}
process.exit(0);
