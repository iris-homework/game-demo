// Patch only the two marked neon signs in decoded V2 GIF frames.
// Retain the source GIF palette: all pixels outside the sign masks stay exact.
import {createRequire} from 'node:module';
import {readFile,writeFile,mkdir,access} from 'node:fs/promises';
import path from 'node:path';
const require=createRequire(import.meta.url);
const sharp=require(process.env.CODEX_NODE_MODULES ? path.join(process.env.CODEX_NODE_MODULES,'sharp') : 'sharp');
const [source,output]=process.argv.slice(2);
if(!source||!output)throw new Error('Usage: node render_noren_neon_patch.mjs SOURCE.gif OUTPUT_DIR');
try {await access(path.join(output,'indices.bin'));throw new Error('Output already exists');}catch(e){if(e.code!=='ENOENT')throw e;}
const gif=await readFile(source);
if(!gif.subarray(0,6).toString().startsWith('GIF')||!(gif[10]&128))throw new Error('Expected GIF with global palette');
const paletteCount=2**((gif[10]&7)+1),palette=Array.from(gif.subarray(13,13+paletteCount*3));
while(palette.length<768)palette.push(0);
const rgbIndex=new Map();
for(let i=0;i<256;i++)rgbIndex.set((palette[i*3]<<16)|(palette[i*3+1]<<8)|palette[i*3+2],i);
const meta=await sharp(source,{animated:true}).metadata();
const {data,info}=await sharp(source,{animated:true}).removeAlpha().raw().toBuffer({resolveWithObject:true});
const width=info.width,height=meta.pageHeight,frameCount=meta.pages;
if(frameCount!==60||width!==1008||height!==567||info.channels!==3)throw new Error('Unexpected V2 dimensions or frames');
const signs=[
 {name:'left_bottle_sign',polygon:[[741,353],[788,364],[795,494],[740,502]],keys:[[0,1],[9,1],[10,.28],[11,.15],[12,.85],[13,1],[20,1],[21,.4],[22,.18],[23,.18],[24,.75],[25,1],[44,1],[45,.30],[46,1],[59,1]]},
 {name:'right_bottle_sign',polygon:[[1510,270],[1572,264],[1585,401],[1521,415]],keys:[[0,1],[15,1],[16,.2],[18,.2],[19,1],[33,1],[34,.15],[35,.65],[36,.2],[37,.2],[38,1],[50,1],[51,.4],[52,1],[59,1]]}
];
function inside(x,y,p){let yes=false;for(let i=0,j=p.length-1;i<p.length;j=i++){const [ax,ay]=p[j],[bx,by]=p[i];if((ay>y)!==(by>y)&&x<(bx-ax)*(y-ay)/(by-ay)+ax)yes=!yes;}return yes;}
function gain(frame,keys){for(let i=1;i<keys.length;i++)if(frame<=keys[i][0]){const [a,av]=keys[i-1],[b,bv]=keys[i];return av+(bv-av)*(frame-a)/(b-a);}return 1;}
const n=width*height,mask=Buffer.alloc(n),owners=new Int8Array(n).fill(-1),indices=Buffer.alloc(n*frameCount);
for(let y=0;y<height;y++)for(let x=0;x<width;x++)for(let s=0;s<signs.length;s++)if(inside((x+.5)*1672/width,(y+.5)*941/height,signs[s].polygon)){mask[y*width+x]=255;owners[y*width+x]=s;}
function closest(r,g,b){let best=0,dist=Infinity;for(let i=0;i<256;i++){const d=(palette[i*3]-r)**2+(palette[i*3+1]-g)**2+(palette[i*3+2]-b)**2;if(d<dist){dist=d;best=i;}}return best;}
const caches=new Map(),changes=[];
await mkdir(output,{recursive:true});
for(let f=0;f<frameCount;f++){
 let changed=0;
 const gains=signs.map(s=>gain(f,s.keys));
 for(let p=0;p<n;p++){
   const i=(f*n+p)*3,r=data[i],g=data[i+1],b=data[i+2],key=(r<<16)|(g<<8)|b;
   let idx=rgbIndex.get(key);if(idx===undefined)throw new Error('Source pixel is not in global palette');
   const owner=owners[p];
   if(owner>=0&&gains[owner]<1&&r>65&&b>35){
     const ck=key+':'+gains[owner];
     if(!caches.has(ck))caches.set(ck,closest(r*gains[owner],g*gains[owner],b*gains[owner]));
     idx=caches.get(ck);
     if(palette[idx*3]!==r||palette[idx*3+1]!==g||palette[idx*3+2]!==b)changed++;
   }
   indices[f*n+p]=idx;
 }
 changes.push({frame:f,gains,changedPixels:changed});
 if([0,11,17,22,34].includes(f)){
   const rgb=Buffer.alloc(n*3);
   for(let p=0;p<n;p++){const k=indices[f*n+p]*3;rgb[p*3]=palette[k];rgb[p*3+1]=palette[k+1];rgb[p*3+2]=palette[k+2];}
   await sharp(rgb,{raw:{width,height,channels:3}}).png().toFile(path.join(output,`preview-${String(f).padStart(3,'0')}.png`));
 }
}
await writeFile(path.join(output,'indices.bin'),indices);
await writeFile(path.join(output,'mask.bin'),mask);
await writeFile(path.join(output,'metadata.json'),JSON.stringify({source,width,height,frame_count:frameCount,durations:meta.delay,loop:meta.loop,palette,signs,changes},null,2)+'\n');
console.log(JSON.stringify({width,height,frames:frameCount,maskPixels:mask.filter(x=>x!==0).length,changedPixels:changes.reduce((s,f)=>s+f.changedPixels,0)}));
