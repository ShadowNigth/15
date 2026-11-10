import fs from 'node:fs';
import {createRequire} from 'node:module';
import {NodeIO} from '@gltf-transform/core';
import {ALL_EXTENSIONS} from '@gltf-transform/extensions';
import {dequantize} from '@gltf-transform/functions';
import {MeshoptDecoder} from 'meshoptimizer';
import {KTX2Decoder, MSCTranscoder} from '@babylonjs/ktx2decoder/index.js';
import sharp from 'sharp';
const require = createRequire(import.meta.url);
const dir = new URL('./node_modules/@babylonjs/ktx2decoder/wasm/',import.meta.url);
// The upstream transcoder is CommonJS-shaped inside an ESM package.
const shim = new URL('./msc.cjs', import.meta.url);
fs.writeFileSync(shim, fs.readFileSync(new URL('msc_basis_transcoder.js', dir)));
MSCTranscoder.JSModule = require(shim.pathname);
fs.unlinkSync(shim);
MSCTranscoder.WasmBinary = fs.readFileSync(new URL('msc_basis_transcoder.wasm',dir));
const decoder = new KTX2Decoder();
const io = new NodeIO().registerExtensions(ALL_EXTENSIONS).registerDependencies({'meshopt.decoder': MeshoptDecoder});
await MeshoptDecoder.ready;
const doc = await io.read(process.argv[2]);
for(const t of doc.getRoot().listTextures()) {
 if(t.getMimeType() !== 'image/ktx2') continue;
 const d = await decoder.decode(t.getImage(),{}, {forceRGBA:true, bypassTranscoders:['UniversalTranscoder_UASTC_RGBA_UNORM','UniversalTranscoder_UASTC_RGBA_SRGB']});
 if(d.errors) throw Error(d.errors);
 const m = d.mipmaps[0];
 t.setImage(await sharp(Buffer.from(m.data),{raw:{width:m.width,height:m.height,channels:4}}).png().toBuffer()).setMimeType('image/png');
}
for(const e of doc.getRoot().listExtensionsUsed()) if(['KHR_texture_basisu','EXT_meshopt_compression'].includes(e.extensionName)) e.dispose();
await doc.transform(dequantize());
await io.write(process.argv[3],doc);
console.log('Converted',process.argv[3]);
