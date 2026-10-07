// Render a small looping animation from the existing illustration.
// Local mesh displacements animate the cup/hand and lower legs; no generated sheet is used.
import { createRequire } from 'node:module';
import { mkdir, writeFile, access } from 'node:fs/promises';
import path from 'node:path';
const require = createRequire(import.meta.url);
const sharp = require(process.env.CODEX_NODE_MODULES
  ? path.join(process.env.CODEX_NODE_MODULES, 'sharp') : 'sharp');
const [input, output, preset = 'subtle'] = process.argv.slice(2);
if (!input || !output) throw new Error('Usage: node render_noren_idle.mjs INPUT.png OUTPUT_DIR [subtle|expressive|motion]');
if (!['subtle', 'expressive', 'motion'].includes(preset)) throw new Error('Unknown animation preset');
await access(input);
try { await access(path.join(output, 'frame-000.png')); throw new Error('Output frames already exist'); }
catch (error) { if (error.code !== 'ENOENT') throw error; }
await mkdir(output, { recursive: true });
const width = 1008, height = 567, count = 60, durationMs = 80;
const { data: base } = await sharp(input).resize(width, height, { fit: 'fill' }).removeAlpha().raw().toBuffer({ resolveWithObject: true });
const sx = 1672 / width, sy = 941 / height;
const smooth = (a, b, v) => { const t = Math.max(0, Math.min(1, (v-a)/(b-a))); return t*t*(3-2*t); };
const shapes = [
  { name: 'cup_and_hand', pivot: [426, 437], angle: 1.65, phase: 0,
    polygon: [[401,341],[449,341],[458,381],[448,411],[435,449],[416,459],[401,440],[396,414],[391,389],[390,362]], feather: 7 },
  { name: 'forward_boot_and_shin', pivot: [459, 568], angle: 1.65, phase: 0.2, hinge: [574,631],
    polygon: [[440,575],[469,583],[451,638],[435,684],[422,731],[407,778],[388,808],[318,802],[310,778],[332,749],[355,723],[367,684],[389,635],[416,596]], feather: 8 },
  { name: 'lower_boot_and_shin', pivot: [490, 577], angle: 1.25, phase: 0.8, hinge: [592,650],
    polygon: [[477,577],[504,581],[513,619],[509,683],[511,724],[518,778],[511,820],[505,856],[452,860],[440,840],[451,803],[459,773],[458,724],[460,682],[464,629]], feather: 7 }
];
if (preset === 'expressive') {
  shapes[0].angle *= 2.4;
  shapes[1].angle *= 2;
  shapes[2].angle *= 2;
}
if (preset === 'motion') {
  shapes[0].angle *= 3;
  shapes[1].angle *= 2.6;
  shapes[2].angle *= 2.6;
}
// Periodic pulses keep each flicker smooth at its edges and the loop seam.
function pulse(phase, center, radius) {
  const d = Math.abs(phase-center);
  return 1-smooth(radius*0.3, radius, Math.min(d,1-d));
}
function lightGains(t) {
  if (preset !== 'expressive') return {warm:0.032*Math.sin(t),neon:0.045*Math.sin(t+0.65)};
  const phase=t/(2*Math.PI);
  return {
    warm:0.04*Math.sin(t)-0.38*pulse(phase,0.18,0.065)-0.30*pulse(phase,0.57,0.045)+0.07*pulse(phase,0.25,0.04),
    neon:0.065*Math.sin(t+0.65)-0.62*pulse(phase,0.31,0.035)-0.48*pulse(phase,0.40,0.027)-0.55*pulse(phase,0.78,0.05)
  };
}
function polygonWeight(x, y, shape) {
  let inside = false, dist2 = Infinity;
  const p = shape.polygon;
  for (let i=0,j=p.length-1;i<p.length;j=i++) {
    const [ax,ay]=p[j], [bx,by]=p[i];
    if ((ay>y)!==(by>y) && x < (bx-ax)*(y-ay)/(by-ay)+ax) inside=!inside;
    const vx=bx-ax, vy=by-ay;
    const t=Math.max(0,Math.min(1,((x-ax)*vx+(y-ay)*vy)/(vx*vx+vy*vy)));
    const dx=x-(ax+t*vx),dy=y-(ay+t*vy);
    dist2=Math.min(dist2,dx*dx+dy*dy);
  }
  let w=smooth(-shape.feather,shape.feather,(inside?1:-1)*Math.sqrt(dist2));
  if(shape.hinge) w*=smooth(shape.hinge[0],shape.hinge[1],y);
  return w;
}
const motion=[];
const lights=[];
function gaussian(x,y,cx,cy,rx,ry) {
  const d=((x-cx)/rx)**2+((y-cy)/ry)**2;
  return d>5?0:Math.exp(-d*2);
}
for(let y=0;y<height;y++) for(let x=0;x<width;x++) {
  const ox=x*sx,oy=y*sy,i=(y*width+x)*3;
  const weights=shapes.map(s=>polygonWeight(ox,oy,s));
  if(weights.some(w=>w>0.0001)) motion.push({x,y,ox,oy,i,weights});
  const warm=Math.max(gaussian(ox,oy,115,62,110,95),gaussian(ox,oy,352,121,118,100),gaussian(ox,oy,646,247,95,95),gaussian(ox,oy,512,363,130,185)*0.35,gaussian(ox,oy,1470,675,90,110));
  const neon=Math.max(gaussian(ox,oy,768,409,37,110),gaussian(ox,oy,1544,334,36,115),gaussian(ox,oy,944,512,134,64));
  if(warm>0.0005 || neon>0.0005) lights.push({i,warm,neon});
}
function sample(buffer, i, x,y) {
  x=Math.max(0,Math.min(width-1.001,x));y=Math.max(0,Math.min(height-1.001,y));
  const x0=Math.floor(x),y0=Math.floor(y),fx=x-x0,fy=y-y0;
  const a=(y0*width+x0)*3,b=a+3,c=a+width*3,d=c+3;
  for(let ch=0;ch<3;ch++) buffer[i+ch]=Math.round((base[a+ch]*(1-fx)+base[b+ch]*fx)*(1-fy)+(base[c+ch]*(1-fx)+base[d+ch]*fx)*fy);
}
const selected=[];
const rawFrames=[];
const lightingTimeline=[];
for(let frame=0;frame<count;frame++) {
  const t=2*Math.PI*frame/count;
  const trig=shapes.map(s=>{
    const a=s.angle*Math.PI/180*Math.sin(t+s.phase);
    return {cos:Math.cos(a),sin:Math.sin(a)};
  });
  const buffer=Buffer.from(base);
  for(const p of motion) {
    let dx=0,dy=0;
    for(let s=0;s<shapes.length;s++) {
      const w=p.weights[s]; if(w===0)continue;
      const px=p.ox-shapes[s].pivot[0],py=p.oy-shapes[s].pivot[1];
      dx+=(px*trig[s].cos+py*trig[s].sin-px)*w;
      dy+=(-px*trig[s].sin+py*trig[s].cos-py)*w;
    }
    sample(buffer,p.i,p.x+dx/sx,p.y+dy/sy);
  }
  const {warm:warmGain,neon:neonGain}=lightGains(t);
  lightingTimeline.push({frame,warmGain,neonGain});
  for(const p of lights) {
    const k=1+p.warm*warmGain+p.neon*neonGain;
    for(let ch=0;ch<3;ch++) buffer[p.i+ch]=Math.max(0,Math.min(255,Math.round(buffer[p.i+ch]*k)));
  }
  const file=path.join(output,`frame-${String(frame).padStart(3,'0')}.png`);
  await sharp(buffer,{raw:{width,height,channels:3}}).png().toFile(file);
  if([0,15,30,45].includes(frame)) selected.push({input:file,top:Math.floor(selected.length/2)*height,left:(selected.length%2)*width});
  if([0,1,15,30,45,59].includes(frame))rawFrames.push({frame,buffer});
}
await sharp({create:{width:width*2,height:height*2,channels:3,background:'#090711'}}).composite(selected).png().toFile(path.join(output,'..','contact-sheet.png'));
function diff(a,b,region=[0,0,width,height]) {
  let sum=0,n=0,max=0;
  for(let y=region[1];y<region[3];y++)for(let x=region[0];x<region[2];x++)for(let c=0;c<3;c++) {
    const d=Math.abs(a[(y*width+x)*3+c]-b[(y*width+x)*3+c]);sum+=d;n++;max=Math.max(max,d);
  }
  return {mean:sum/n,max};
}
const get=f=>rawFrames.find(x=>x.frame===f).buffer;
const metrics={input,preset,width,height,frameCount:count,durationMs,totalDurationMs:count*durationMs,technique:'Local inverse-mapped mesh animation with smooth boundary weights; periodic local lighting. Original face and architecture not regenerated.',parameters:shapes,lightingTimeline,firstStep:diff(get(0),get(1)),loopSeam:diff(get(59),get(0)),quarterCycle:diff(get(0),get(15)),staticStaircase:diff(get(0),get(15),[790,210,910,310])};
await writeFile(path.join(output,'..','render-metrics.json'),JSON.stringify(metrics,null,2)+'\n');
console.log(JSON.stringify({width,height,frameCount:count,totalDurationMs:count*durationMs,loopSeam:metrics.loopSeam,staticStaircase:metrics.staticStaircase}));
