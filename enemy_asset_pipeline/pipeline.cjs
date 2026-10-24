"use strict";
const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");
const {characterNames,characterLabel,displayReport}=require("./character_names.cjs");
const zlib = require("node:zlib");
const {buildRuntimeData,stableBindingKey} = require("./vendor/xsxb/tools/runtime_data");
const {opaqueBoundsForPng} = require("./vendor/xsxb/tools/box_estimator");
const {pngInfo} = require("./vendor/xsxb/tools/attack_trails");
const {scanSource} = require("./asset_discovery.cjs");
const {
  ATTACK_STYLES,
  EFFECT_SLOTS,
  createAttackTemplate,
  normalizeAttacks,
  validateAttackPoses,
  validateTexturePath,
} = require("./attack_templates.cjs");
const ROOT = __dirname;
const GAME = path.resolve(ROOT,"..");
const ID = /^[a-z][a-z0-9_]{0,63}$/;
const ACTIONS = new Set(["idle","move","hit","slash","pierce","block","damaged","shoot","laser","bite","bite_close","retreat","gun_idle","gun_block","gun_damaged","evade","blunt"]);
const STYLES = new Set(["","hit","slash","pierce","shoot","laser","bite"]);
const NOR = {idle:[[710,1240],.099],move:[[920,1048],.103],slash:[[725,1110],.103],pierce:[[1000,941],.132],block:[[550,1140],.103],damaged:[[700,1230],.099],gun_idle:[[660,1230],.099],shoot:[[714,1210],.099],retreat:[[560,1155],.099],gun_block:[[550,1140],.103],gun_damaged:[[700,1230],.099]};
const IDLES = {warden_shield:["01a_warden_shield/warden_shield_idle.png","巡界盾手"],scavenger_hooker:["02b_scavenger_hooker/scavenger_hooker_idle.png","拾荒钩客"],chip_broker:["04b_chip_broker/chip_broker_idle.png","筹码掮客"],mutant_mouse:["05a_mutant_mouse/mutant_mouse.png","爬墙线鼠"],luggage_lurker:["06b_luggage_lurker/luggage_lurker_idle.png","行李潜伏客"],penitent_ascetic:["07b_penitent_ascetic/penitent_ascetic_idle.png","赎罪苦修者"],rogue_drone:["08b_rogue_drone/rogue_drone_idle.png","失控配送蜂"],pruning_hound:["10a_pruning_hound/pruning_hound_idle.png","修枝猎犬"],powerline_repairman:["11a_powerline_repairman/powerline_repairman_idle.png","输电抢修工"],beacon_jellyfish:["13b_beacon_jellyfish/beacon_jellyfish_idle.png","信标水母"]};
const DISCOVERY_LABELS = {mirror_inspector:"镜面监察员"};
const MOVED = {fish:"12a_fish",robot:"02b_robot",gang_boss:"03b_gang_boss",gang_henchman:"03a_gang_henchman"};
const clone = x => JSON.parse(JSON.stringify(x));
function read(file,fallback={}) { if(!fs.existsSync(file)) return clone(fallback); return JSON.parse(fs.readFileSync(file,"utf8").replace(/^\uFEFF/,"")); }
function write(file,data) { fs.mkdirSync(path.dirname(file),{recursive:true}); fs.writeFileSync(file+".tmp",JSON.stringify(data,null,2)+"\n"); fs.renameSync(file+".tmp",file); }
function inside(root,relative) { const full=path.resolve(root,relative); if(full!==root&&!full.startsWith(root+path.sep)) throw Error("路径超出允许目录"); return full; }
function number(x,min,max,label) { if(typeof x!=="number"||!Number.isFinite(x)||x<min||x>max) throw Error(`${label} 应为 ${min}～${max} 的数值`); return x; }
function vec(x,label) { if(!Array.isArray(x)||x.length!==2) throw Error(`${label} 需要两个坐标`); return x.map(v=>number(v,-100000,100000,label)); }
function currentPath(p) { for(const [old,next] of Object.entries(MOVED)) p=p.replace(`/combat_test/${old}/`,`/combat_test/${next}/`); return p; }
function resource(p) { return "res://"+path.relative(GAME,p).replaceAll("\\","/"); }
function defaults(visual) { return {visual,shadow:{enabled:true,size:[32,9],offset:[0,2],opacity:.7},motion:{speed:2300,reach:visual.attackStyleOverride==="pierce"?105:86,windup:.045,recovery:.12},effects:{scale:1,offset:[0,0]},frameAnchors:{}}; }
function createPipeline(options={}) {
  const workRoot=options.workRoot||path.join(ROOT,"authoring");
  const data=path.join(workRoot,"data/projects/midnight");
  const manifestFile=path.join(data,"animation_manifest.json"), tuningFile=path.join(data,"animation_tuning.json"), metadataFile=path.join(data,"midnight.json");
  const defaultSourceRoot=path.join(GAME,"assets/combat_test");
  const sourceRoot=options.sourceRoot?path.resolve(GAME,options.sourceRoot):defaultSourceRoot;
  const scanReportFile=path.join(data,"asset_scan_report.json");
  let lastScanReport=null;
  const publishedFile=options.publishedFile||path.join(ROOT,"published/catalog.json");
  const referenceFile=options.referenceFile?path.resolve(options.referenceFile):path.join(ROOT,"published/catalog.json");
  const previewFile=options.previewFile||path.join(ROOT,"authoring/preview_catalog.json");
  function asset(p) { if(p.startsWith("res://")) return inside(GAME,p.slice(6)); if(p.startsWith("game/")) return inside(GAME,p.slice(5)); return inside(workRoot,p); }
  function resourcePaths(value) {
    if(Array.isArray(value)) return value.map(resourcePaths);
    if(!value||typeof value!=="object") return value;
    return Object.fromEntries(Object.entries(value).map(([key,x])=>[key,typeof x==="string"&&/^(path|assetPath|sourceAssetPath|texturePath|texture|imagePath|audioPath)$/i.test(key)&&x&&!x.startsWith("data:")?resource(asset(x)):resourcePaths(x)]));
  }
  function load() { return {manifest:read(manifestFile,{schemaVersion:1,profiles:[]}),tuning:read(tuningFile,{schemaVersion:1,values:{},scene_settings:{},frame_visual_overrides:{},frame_playback_overrides:{},frame_box_overrides:{}}),metadata:read(metadataFile,{profiles:{}})}; }
  function save(state) { write(manifestFile,state.manifest); write(tuningFile,state.tuning); write(metadataFile,state.metadata); }
  function seed() {
    fs.mkdirSync(workRoot,{recursive:true}); fs.writeFileSync(path.join(workRoot,".gdignore"),"");
    write(path.join(workRoot,"data/projects.json"),{schemaVersion:1,activeProjectId:"midnight",projects:[{id:"midnight",label:"午夜委托 · 怪物制作",kind:"frame_lite",projectRoot:"",dataDir:"data/projects/midnight",workspaceDir:"workspace/projects/midnight"}]});
    const state=load();
    if(!state.manifest.profiles.length) {
      const visuals=read(path.join(GAME,"data/enemies/combat_visuals.json"));
      const enemies=Object.values(read(path.join(GAME,"data/enemies/enemies.json")));
      for(const [id,v] of Object.entries(visuals)) {
        for(const entry of Object.values(v.poses)) entry.texture=currentPath(entry.texture);
        if(v.hitEffectTexture) v.hitEffectTexture=currentPath(v.hitEffectTexture);
        v.label=enemies.find(e=>e.combatVisualId===id)?.displayName||id;
      }
      visuals.noren={id:"noren",label:"noren",sourceFacing:"left",targetRect:[-58,-130,116,145],poses:Object.fromEntries(Object.entries(NOR).map(([pose,[anchor,scale]])=>[pose,{anchor,scale,texture:`res://assets/combat_test/noren/noren_${pose==="shoot"?"shoot_planted":pose}.png`}]))};
      for(const [id,[rel,label]] of Object.entries(IDLES)) {
        const full=path.join(GAME,"assets/combat_test",rel); if(!fs.existsSync(full)) continue;
        const b=opaqueBoundsForPng(full); const info=pngInfo(fs.readFileSync(full));
        const left=b?.x||0,top=b?.y||0,width=b?.width||info.width,height=b?.height||info.height;
        visuals[id]={id,label,sourceFacing:"left",targetRect:[-65,-145,130,155],poses:{idle:{texture:resource(full),anchor:[left+width/2,top+height],scale:140/height}}};
      }
      for(const [id,visual] of Object.entries(visuals)) {
        const profile={id,label:visual.label||id,kind:"actor",bodyScale:1,runtimeScale:1,animations:[]};
        for(const [pose,entry] of Object.entries(visual.poses)) {
          const full=inside(GAME,entry.texture.replace(/^res:\/\//,"")); if(!fs.existsSync(full)||path.extname(full).toLowerCase()!==".png") continue;
          const info=pngInfo(fs.readFileSync(full));
          profile.animations.push({id:pose,name:pose,anchorMode:"canvas_bottom_center",sourceAnchor:{x:entry.anchor[0],y:entry.anchor[1]},defaultScale:entry.scale,fps:8,loop:["idle","move","gun_idle"].includes(pose),frames:[{name:path.basename(full),path:"game/"+entry.texture.slice(6),width:info.width,height:info.height,duration:1}]});
        }
        if(!profile.animations.length) continue;
        state.manifest.profiles.push(profile); state.metadata.profiles[id]=defaults(visual);
      }
      save(state);
    }
    scanAssets({trigger:"seed"});
    return load();
  }
  function publicSourcePath(full) {
    const relative=path.relative(GAME,full);
    if(relative!==".."&&!relative.startsWith(".."+path.sep)&&!path.isAbsolute(relative))return relative.replaceAll("\\","/");
    return full.replaceAll("\\","/");
  }
  function positiveNumber(value) { const number=Number(value); return Number.isFinite(number)&&number>0?number:null; }
  function groupScaleY(tuning,profileId,animation) {
    const base=`profiles.${profileId}.groups.${animation.id}`,values=tuning.values||{};
    const scalar=positiveNumber(values[`${base}.visual_size`])??positiveNumber(animation.defaultScale)??1;
    const scale=values[`${base}.visual_scale`];
    if(typeof scale==="number"&&positiveNumber(scale))return positiveNumber(scale);
    if(scale&&typeof scale==="object"&&positiveNumber(scale.y))return positiveNumber(scale.y);
    return scalar;
  }
  function frameScaleY(tuning,profileId,animationId,baseScale) {
    const override=(tuning.frame_visual_overrides||{})[`${profileId}/${animationId}:0`];
    if(!override||typeof override!=="object")return baseScale;
    const scalar=positiveNumber(override.visual_size)??baseScale;
    const scale=override.visual_scale;
    if(typeof scale==="number"&&positiveNumber(scale))return positiveNumber(scale);
    if(scale&&typeof scale==="object"&&positiveNumber(scale.y))return positiveNumber(scale.y);
    return scalar;
  }
  function idleBaseline(state,profile) {
    const idle=profile.animations.find(animation=>animation.id==="idle");
    if(!idle||!idle.frames?.length)return null;
    const base=groupScaleY(state.tuning,profile.id,idle),effectiveScale=frameScaleY(state.tuning,profile.id,"idle",base);
    let visibleHeight=positiveNumber(idle.frames[0].height);
    try{const full=asset(idle.frames[0].path);if(fs.existsSync(full)){const bounds=opaqueBoundsForPng(full);if(positiveNumber(bounds?.height))visibleHeight=positiveNumber(bounds.height);}}catch{}
    if(!positiveNumber(visibleHeight)||!positiveNumber(effectiveScale))return null;
    return {profileId:profile.id,animationId:"idle",visibleHeight,effectiveScale};
  }
  function readScanPng(descriptor) {
    const bytes=fs.readFileSync(descriptor.fullPath);
    if(!bytes.length)throw Error("PNG 文件为空");
    if(bytes.length<33||!bytes.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10])))throw Error("文件不是PNG");
    let offset=8,ended=false;const imageData=[];
    while(offset+12<=bytes.length){
      const length=bytes.readUInt32BE(offset);
      if(length>bytes.length-offset-12)throw Error("PNG 分块截断");
      const type=bytes.toString("ascii",offset+4,offset+8);
      if(type==="IDAT")imageData.push(bytes.subarray(offset+8,offset+8+length));
      if(type==="IEND"){ended=true;break;}
      offset+=length+12;
    }
    if(!imageData.length)throw Error("PNG 缺少图像数据");
    if(!ended)throw Error("PNG 缺少 IEND");
    try{zlib.inflateSync(Buffer.concat(imageData));}catch{throw Error("PNG 图像数据损坏");}
    const info=pngInfo(bytes);
    if(!Number.isInteger(info.width)||!Number.isInteger(info.height)||info.width<=0||info.height<=0)throw Error("PNG 缺少有效尺寸");
    const bounds=opaqueBoundsForPng(descriptor.fullPath);
    if(!bounds||!positiveNumber(bounds.width)||!positiveNumber(bounds.height)||!positiveNumber(bounds.canvasWidth)||!positiveNumber(bounds.canvasHeight))throw Error("PNG 不透明边界无效");
    return {bytes,info,bounds};
  }
  function copyDiscoveredAsset(profileId,scope,bytes) {
    const hash=crypto.createHash("sha256").update(bytes).digest("hex");
    const relative=path.posix.join("workspace/projects/midnight/discovered",profileId,scope,hash+".png");
    const full=asset(relative);
    fs.mkdirSync(path.dirname(full),{recursive:true});
    if(!fs.existsSync(full)||!fs.readFileSync(full).equals(bytes))fs.writeFileSync(full,bytes);
    return {framePath:relative,fullPath:full};
  }
  function resolveScanAsset(descriptor,kind,profileId,bytes,gamePaths) {
    if(gamePaths)return {framePath:"game/"+path.relative(GAME,descriptor.fullPath).replaceAll("\\","/"),fullPath:descriptor.fullPath};
    return copyDiscoveredAsset(profileId,kind==="effect"?"effects":descriptor.action,bytes);
  }
  function validateAttackResources(attacks) {
    const resourceFields=["muzzleTexture","projectileTexture","impactTexture"];
    for(const [style,entry] of Object.entries(attacks))for(const field of resourceFields){
      const texture=validateTexturePath(entry[field],`攻击模板 ${style}.${field}`);
      if(!texture)continue;
      const full=inside(GAME,texture.slice(6));
      let real;
      try{real=fs.realpathSync(full);}catch{throw Error(`攻击模板 ${style}.${field} 资源不存在：${texture}`);}
      const realGame=fs.realpathSync(GAME),relative=path.relative(realGame,real);
      if(relative===".."||relative.startsWith(`..${path.sep}`)||path.isAbsolute(relative))throw Error(`攻击模板 ${style}.${field} 路径超出游戏目录`);
      if(!fs.statSync(real).isFile()||path.extname(real).toLowerCase()!==".png")throw Error(`攻击模板 ${style}.${field} 必须是 PNG 文件`);
      const info=pngInfo(fs.readFileSync(real));
      if(!info.width||!info.height)throw Error(`攻击模板 ${style}.${field} 图片损坏`);
    }
  }
  function addScannedAttackTemplate(profile,meta,descriptor) {
    const style=descriptor.attackStyle;
    if(descriptor.legacyAttack)return null;
    if(!ATTACK_STYLES.includes(style))return null;
    if(!meta.attacks||typeof meta.attacks!=="object"||Array.isArray(meta.attacks))meta.attacks={};
    if(Object.hasOwn(meta.attacks,style))return null;
    meta.attacks[style]=createAttackTemplate(style,profile.animations.map(animation=>animation.id));
    return style;
  }
  function attachScannedAttackEffect(meta,slot,texture) {
    const field=`${slot}Texture`;
    const attacks=meta.attacks&&typeof meta.attacks==="object"&&!Array.isArray(meta.attacks)?meta.attacks:{};
    const styles=Object.keys(attacks).filter(style=>ATTACK_STYLES.includes(style));
    if(styles.length!==1)return {attachedStyle:null,candidateCount:styles.length};
    const style=styles[0],entry=attacks[style];
    if(!entry||typeof entry!=="object"||Array.isArray(entry))return {attachedStyle:null,candidateCount:1};
    if(entry[field]!==""&&entry[field]!==undefined)return {attachedStyle:null,candidateCount:1,existingTexture:true};
    entry[field]=texture;
    return {attachedStyle:style,candidateCount:1};
  }
  function scanAssets(scanOptions={}) {
    try {
      const source=scanSource(sourceRoot,{actions:ACTIONS});
      const state=load(),report={schemaVersion:1,ok:true,trigger:scanOptions.trigger||"manual",scannedAt:new Date().toISOString(),sourceRoot:publicSourcePath(source.sourceRoot),scannedDirectories:source.directories.length,scannedFiles:source.files.length+source.skipped.filter(entry=>entry.file.toLowerCase().endsWith(".png")).length,addedProfiles:[],addedActions:[],addedAttacks:[],addedEffects:[],skipped:[...source.skipped],warnings:[...source.warnings],missingIdle:[],unchanged:true};
      const changed={manifest:false,metadata:false};
      const profiles=new Map(state.manifest.profiles.map(profile=>[profile.id,profile]));
      const scannedRoles=new Set(source.directories.map(entry=>entry.role));
      const noBaselineWarned=new Set();
      const legacyAttackWarned=new Set();
      const importedAttackStyles=new Map();
      const enemies=Object.values(read(path.join(GAME,"data/enemies/enemies.json")));
      const labels=new Map(enemies.filter(enemy=>enemy.combatVisualId).map(enemy=>[enemy.combatVisualId,enemy.displayName]));
      const labelFor=id=>labels.get(id)||DISCOVERY_LABELS[id]||id;
      let gamePaths=false;
      try{gamePaths=fs.realpathSync(source.sourceRoot)===fs.realpathSync(defaultSourceRoot);}catch{}
      function ensureProfile(role,descriptor) {
        let profile=profiles.get(role),meta=state.metadata.profiles[role];
        if(!profile){
          const label=labelFor(role);
          profile={id:role,label,kind:"actor",bodyScale:1,runtimeScale:1,animations:[]};
          state.manifest.profiles.push(profile);profiles.set(role,profile);changed.manifest=true;
          report.addedProfiles.push({id:role,label,sourceDirectory:descriptor.directory});
        }
        if(!meta){
          meta=defaults({id:role,label:profile.label||labelFor(role),sourceFacing:"left",targetRect:[-65,-145,130,155],poses:{}});
          state.metadata.profiles[role]=meta;changed.metadata=true;
          if(profile.animations?.length)report.warnings.push({code:"missingMetadata",profileId:role,message:"角色已有动作但缺少演出配置，已补默认值"});
        }
        if(!meta.visual||typeof meta.visual!=="object"){
          meta.visual={id:role,label:profile.label||labelFor(role),sourceFacing:"left",targetRect:[-65,-145,130,155],poses:{}};changed.metadata=true;
        }
        if(!Array.isArray(profile.animations))profile.animations=[];
        return {profile,meta};
      }
      const actionPriority={idle:0,move:1,pierce:2,damaged:3};
      const actionFiles=source.files.filter(file=>file.kind==="action").sort((left,right)=>{
        if(left.role!==right.role)return left.role<right.role?-1:1;
        const leftPriority=Object.hasOwn(actionPriority,left.action)?actionPriority[left.action]:10;
        const rightPriority=Object.hasOwn(actionPriority,right.action)?actionPriority[right.action]:10;
        if(leftPriority!==rightPriority)return leftPriority-rightPriority;
        return left.relative<right.relative?-1:left.relative>right.relative?1:0;
      });
      for(const descriptor of actionFiles){
        // A legacy attack can be renamed to a typed attack after calibration.
        // Repair only the exact missing legacy source and a unique typed candidate;
        // keep the old action and all its per-frame calibration intact.
        if(descriptor.styleConfirmed&&descriptor.action!=="bite_close"){
          const candidates=actionFiles.filter(file=>file.role===descriptor.role&&file.styleConfirmed&&file.action!=="bite_close");
          const existing=profiles.get(descriptor.role);
          if(candidates.length===1&&existing){
            for(const animation of existing.animations||[])for(const frame of animation.frames||[]){
              if(!frame.path||fs.existsSync(asset(frame.path)))continue;
              if(path.basename(frame.path).toLowerCase()!==`${descriptor.role}_attack.png`)continue;
              let decoded;
              try{decoded=readScanPng(descriptor);}catch{continue;}
              const resolved=resolveScanAsset(descriptor,"action",descriptor.role,decoded.bytes,gamePaths);
              const previous=frame.path;
              frame.path=resolved.framePath;
              frame.name=descriptor.fileName;
              frame.width=decoded.info.width;
              frame.height=decoded.info.height;
              changed.manifest=true;
              report.warnings.push({code:"renamedLegacyAttack",profileId:descriptor.role,message:`旧攻击源文件已改名：${previous} → ${descriptor.relative}；保留 ${animation.id} 动作及原校准。`});
            }
          }
        }
        if(descriptor.legacyAttack&&!legacyAttackWarned.has(descriptor.role)){
          legacyAttackWarned.add(descriptor.role);
          report.warnings.push({code:"legacyAttackNoStyle",profileId:descriptor.role,file:descriptor.relative,message:"旧 attack 文件名未标明攻击类型，暂按 pierce 兼容映射；请确认并手工选择攻击类型。"});
        }
        const existingProfile=profiles.get(descriptor.role);
        if(existingProfile?.animations?.some(animation=>animation.id===descriptor.action)){
          report.skipped.push({file:descriptor.relative,reason:"actionExists",message:"动作已存在，保留原动作、顺序与调参"});
          continue;
        }
        const existingMeta=state.metadata.profiles[descriptor.role];
        if(existingMeta?.visual?.poses?.[descriptor.action]){
          report.skipped.push({file:descriptor.relative,reason:"existingPose",message:"已有手工姿势配置，保留原配置"});
          continue;
        }
        let decoded;
        try{decoded=readScanPng(descriptor);}catch(error){report.skipped.push({file:descriptor.relative,reason:"invalidPng",message:error.message});continue;}
        const {profile}=ensureProfile(descriptor.role,descriptor);
        const baseline=descriptor.action==="idle"?null:idleBaseline(state,profile);
        let scale;
        if(descriptor.action==="idle")scale=140/decoded.bounds.height;
        else if(baseline)scale=baseline.effectiveScale*baseline.visibleHeight/decoded.bounds.height;
        else{
          scale=140/decoded.bounds.height;
          if(!noBaselineWarned.has(descriptor.role)){
            noBaselineWarned.add(descriptor.role);
            report.warnings.push({code:"noIdleScaleBaseline",profileId:descriptor.role,message:"缺少 idle 轮廓基准，动作缩放按 140 像素可见高度估算"});
          }
        }
        if(!positiveNumber(scale)){
          report.skipped.push({file:descriptor.relative,reason:"invalidScale",message:"无法从图片轮廓估算缩放"});
          continue;
        }
        const resolved=resolveScanAsset(descriptor,"action",descriptor.role,decoded.bytes,gamePaths);
        const anchor={x:decoded.bounds.x+decoded.bounds.width/2,y:decoded.bounds.y+decoded.bounds.height};
        const animation={id:descriptor.action,name:descriptor.actionName||descriptor.action,anchorMode:"canvas_bottom_center",sourceAnchor:anchor,defaultScale:Number(scale.toFixed(6)),fps:8,loop:["idle","move","gun_idle"].includes(descriptor.action),frames:[{name:descriptor.fileName,path:resolved.framePath,width:decoded.info.width,height:decoded.info.height,duration:1}]};
        profile.animations.push(animation);changed.manifest=true;
        const {meta}=ensureProfile(descriptor.role,descriptor);
        const attackStyle=addScannedAttackTemplate(profile,meta,descriptor);
        if(attackStyle){
          changed.metadata=true;
          report.addedAttacks.push({profileId:descriptor.role,style:attackStyle,file:descriptor.relative});
          if(!importedAttackStyles.has(descriptor.role))importedAttackStyles.set(descriptor.role,new Set());
          importedAttackStyles.get(descriptor.role).add(attackStyle);
        }
        report.addedActions.push({profileId:descriptor.role,action:descriptor.action,name:animation.name,mappedFrom:descriptor.mappedFrom,attackStyle:descriptor.attackStyle||null,legacyAttack:descriptor.legacyAttack,file:descriptor.relative,framePath:resolved.framePath,anchor,defaultScale:animation.defaultScale,estimated:true,calibrationRequired:true,baseline:baseline||{targetVisibleHeight:140},note:"自动估算脚底与大小，需在制作台校准"});
      }
      for(const [role,newStyles] of importedAttackStyles){
        const meta=state.metadata.profiles[role];
        if(!meta)continue;
        const styles=Object.keys(meta.attacks||{}).filter(style=>ATTACK_STYLES.includes(style));
        const override=meta.visual.attackStyleOverride||"";
        const manual=meta.attackStyleManual===true||(!!override&&meta.attackStyleAuto!==true);
        if(manual)continue;
        if(styles.length>=2){
          if(meta.attackStyleAuto){meta.visual.attackStyleOverride="";delete meta.attackStyleAuto;changed.metadata=true;}
          report.warnings.push({
            code:"multipleAttackStylesNeedSelection",
            profileId:role,
            styles,
            newlyImported:[...newStyles],
            message:role==="noren"
              ? `noren 检测到多个攻击模板（${styles.join("、")}）；保持按卡牌／形态选择，不自动设置默认攻击类型。`
              : `角色 ${role} 检测到多个攻击模板（${styles.join("、")}）；未自动选择文件顺序中的第一项，请人工设置默认攻击类型。`,
          });
        }else if(styles.length===1){
          const style=styles[0];
          if(role!=="noren"){
            meta.visual.attackStyleOverride=style;
            meta.attackStyleAuto=true;
            changed.metadata=true;
            report.warnings.push({code:"attackStyleSuggested",profileId:role,style,message:`仅识别到攻击模板 ${style}，已建议为默认攻击类型；人工选择不会被覆盖。`});
          }
        }
      }
      const effectFiles=source.files.filter(file=>file.kind==="effect").sort((left,right)=>left.relative<right.relative?-1:left.relative>right.relative?1:0);
      for(const descriptor of effectFiles){
        const profile=profiles.get(descriptor.role);
        if(!profile){
          report.skipped.push({file:descriptor.relative,reason:"profileMissing",message:"仅有 VFX、没有可导入动作的角色不建立草稿"});
          continue;
        }
        const existingMeta=state.metadata.profiles[descriptor.role];
        if(descriptor.effectSlot==="vfx"&&existingMeta?.visual?.hitEffectTexture){
          report.skipped.push({file:descriptor.relative,reason:"existingHitEffectTexture",message:"已有命中特效，保留原配置"});
          continue;
        }
        if(descriptor.effectSlot!=="vfx"&&existingMeta?.attackEffects?.[descriptor.effectSlot]){
          report.skipped.push({file:descriptor.relative,reason:"existingAttackEffectTexture",effectSlot:descriptor.effectSlot,message:`已有 ${descriptor.effectSlot} 特效配置，保留原配置`});
          continue;
        }
        let decoded;
        try{decoded=readScanPng(descriptor);}catch(error){report.skipped.push({file:descriptor.relative,reason:"invalidPng",message:error.message});continue;}
        const {meta}=ensureProfile(descriptor.role,descriptor);
        const resolved=resolveScanAsset(descriptor,"effect",descriptor.role,decoded.bytes,gamePaths);
        const texture=resource(resolved.fullPath);
        if(descriptor.effectSlot==="vfx"){
          meta.visual.hitEffectTexture=texture;
          meta.discoveredVfx={texture:meta.visual.hitEffectTexture,source:publicSourcePath(descriptor.fullPath),status:"pending-calibration",note:"自动发现；仅作为待校准素材，未切图或绑定挂件"};
        }else{
          if(!meta.attackEffects||typeof meta.attackEffects!=="object"||Array.isArray(meta.attackEffects))meta.attackEffects={};
          if(!EFFECT_SLOTS.includes(descriptor.effectSlot)){
            report.skipped.push({file:descriptor.relative,reason:"invalidEffectSlot",message:"未知攻击特效槽"});
            continue;
          }
          meta.attackEffects[descriptor.effectSlot]=texture;
          const attachment=attachScannedAttackEffect(meta,descriptor.effectSlot,texture);
          if(attachment.attachedStyle){
            report.addedEffects.push({profileId:descriptor.role,file:descriptor.relative,effectSlot:descriptor.effectSlot,texture,attackStyle:attachment.attachedStyle,status:"pending-calibration",calibrationRequired:true});
          }else{
            report.addedEffects.push({profileId:descriptor.role,file:descriptor.relative,effectSlot:descriptor.effectSlot,texture,status:"pending-association",calibrationRequired:true});
            report.warnings.push({code:"attackEffectNeedsExplicitAssociation",profileId:descriptor.role,effectSlot:descriptor.effectSlot,file:descriptor.relative,message:`已保存 ${descriptor.effectSlot} 特效，但存在多个攻击模板或已有手工纹理；请在攻击模板中明确引用。`});
          }
        }
        changed.metadata=true;
        if(descriptor.effectSlot==="vfx")report.addedEffects.push({profileId:descriptor.role,file:descriptor.relative,effectSlot:"vfx",texture:meta.visual.hitEffectTexture,status:"pending-calibration",calibrationRequired:true});
      }
      for(const role of [...scannedRoles].sort()){
        const profile=profiles.get(role);
        if(!profile)continue;
        const actions=profile.animations.map(animation=>animation.id);
        if(actions.includes("idle"))continue;
        report.missingIdle.push(role);
        report.warnings.push({code:"missingIdle",profileId:role,message:`${profile.label||role} 缺少 idle；已有动作可导入，但发布仍会被校验阻止`});
      }
      if(changed.manifest)write(manifestFile,state.manifest);
      if(changed.metadata)write(metadataFile,state.metadata);
      report.unchanged=!changed.manifest&&!changed.metadata;
      report.revision=revision();
      report.skipped.sort((left,right)=>left.file<right.file?-1:left.file>right.file?1:0);
      lastScanReport=report;
      try{write(scanReportFile,report);}catch(error){report.warnings.push({code:"reportWriteFailed",message:error.message});}
      return report;
    }catch(error){
      const report={schemaVersion:1,ok:false,trigger:scanOptions.trigger||"manual",scannedAt:new Date().toISOString(),sourceRoot:publicSourcePath(sourceRoot),addedProfiles:[],addedActions:[],addedAttacks:[],addedEffects:[],skipped:[],warnings:[{code:"scanFailed",message:error.message}],missingIdle:[],unchanged:true};
      lastScanReport=report;
      try{write(scanReportFile,report);}catch{}
      return report;
    }
  }
  function status() {
    const s=load(),names=characterNames();let autoImport=lastScanReport;
    if(!autoImport)try{autoImport=read(scanReportFile,null);}catch{}
    return {enemies:Object.values(read(path.join(GAME,"data/enemies/enemies.json"))).map(e=>({id:e.id,label:characterLabel(e.combatVisualId||"unillustrated",names),visualId:e.combatVisualId})),profiles:s.manifest.profiles.map(p=>({...s.metadata.profiles[p.id],id:p.id,label:characterLabel(p.id,names),actions:p.animations.map(a=>({id:a.id,count:a.frames.length,anchor:a.sourceAnchor}))})),characterNames:names,published:Object.keys(read(publishedFile,{profiles:{}}).profiles),test:!!options.test,revision:revision(),preview:read(previewFile,{revision:"",profiles:{}}).revision,autoImport:displayReport(autoImport,names),autoImportReport:path.relative(workRoot,scanReportFile).replaceAll("\\","/")};
  }
  function revision() { const s=load(); for(const name of ["frame_audio_bindings.json","frame_image_attachments.json","attack_trails.json"])s[name]=read(path.join(data,name),null); return crypto.createHash("sha256").update(JSON.stringify(s)).digest("hex").slice(0,16); }
  function norenReference() {
    const defaultShadow={enabled:true,size:[32,9],offset:[0,2],opacity:.7};
    const finite=(value,label)=>{if(typeof value!=="number"||!Number.isFinite(value))throw Error(`noren参考${label}无效`);return value;};
    const pair=(value,label,min=-Infinity)=>{if(!Array.isArray(value)||value.length!==2)throw Error(`noren参考${label}需要两个数值`);return value.map(v=>{const n=finite(v,label);if(n<min)throw Error(`noren参考${label}超出范围`);return n;});};
    const transformValue=value=>{if(!Array.isArray(value)||value.length!==6)throw Error("noren参考变换需要六个数值");return value.map(v=>finite(v,"变换"));};
    const shadowValue=value=>{
      if(value===undefined)return clone(defaultShadow);
      if(!value||typeof value!=="object"||Array.isArray(value))throw Error("noren参考阴影无效");
      const enabled=value.enabled===undefined?true:value.enabled;
      if(typeof enabled!=="boolean")throw Error("noren参考阴影开关无效");
      const size=value.size===undefined?[32,9]:pair(value.size,"阴影尺寸",0);
      const offset=value.offset===undefined?[0,2]:pair(value.offset,"阴影偏移");
      const opacity=value.opacity===undefined ? .7 : finite(value.opacity,"阴影透明度");
      if(opacity<0||opacity>1)throw Error("noren参考阴影透明度超出范围");
      return {enabled,size,offset,opacity};
    };
    const pngReference=texture=>{
      if(typeof texture!=="string"||!texture.startsWith("res://"))throw Error("noren参考纹理必须是 res:// PNG");
      const normalized=texture.replaceAll("\\","/");
      const full=inside(GAME,normalized.slice(6));
      const realRoot=fs.realpathSync(GAME),realFile=fs.realpathSync(full);
      const relative=path.relative(realRoot,realFile);
      if(relative===".."||relative.startsWith(".."+path.sep)||path.isAbsolute(relative))throw Error("noren参考纹理超出游戏目录");
      if(!fs.statSync(realFile).isFile()||path.extname(realFile).toLowerCase()!==".png")throw Error("noren参考纹理不是 PNG 文件");
      const bounds=opaqueBoundsForPng(realFile);
      if(!bounds||![bounds.canvasWidth,bounds.canvasHeight,bounds.width,bounds.height].every(v=>Number.isInteger(v)&&v>0))throw Error("noren参考图片无法读取");
      return {texture:normalized,imageUrl:"/asset?path="+encodeURIComponent("game/"+normalized.slice(6)),bounds:{x:bounds.x,y:bounds.y,width:bounds.width,height:bounds.height},width:bounds.canvasWidth,height:bounds.canvasHeight};
    };
    const builtin=()=>{
      const anchor=[710,1240],scale=.099,mirror=-1;
      return {...pngReference("res://assets/combat_test/noren/noren_idle.png"),transform:[scale*mirror,0,0,scale,-anchor[0]*scale*mirror,-anchor[1]*scale],source:"builtin",shadow:clone(defaultShadow)};
    };
    const published=()=>{
      const catalog=read(referenceFile,{profiles:{}}),profile=catalog?.profiles?.noren;
      if(catalog.schemaVersion!==1)throw Error("noren参考正式目录版本无效");
      if(!profile||typeof profile!=="object"||Array.isArray(profile))throw Error("正式目录缺少noren配置");
      if(!["left","right"].includes(profile.sourceFacing))throw Error("noren参考朝向无效");
      let texture,transform;
      const idleFrames=profile.pipelineFrames?.idle;
      if(idleFrames!==undefined&&!Array.isArray(idleFrames))throw Error("noren参考帧配置无效");
      if(idleFrames?.length){
        const frame=idleFrames[0];
        if(!frame||typeof frame!=="object"||Array.isArray(frame))throw Error("noren参考首帧无效");
        texture=frame.texture;
        transform=transformValue(frame.transform);
      }else{
        const pose=profile.poses?.idle;
        if(!pose||typeof pose!=="object"||Array.isArray(pose))throw Error("正式目录缺少noren idle 姿势");
        texture=pose.texture;
        const anchor=pair(pose.anchor,"脚底锚点");
        const scale=finite(pose.scale,"缩放");
        if(scale<=0)throw Error("noren参考缩放必须大于零");
        transform=[scale,0,0,scale,-anchor[0]*scale,-anchor[1]*scale];
      }
      const mirror=profile.sourceFacing==="left"?-1:1;
      transform=[transform[0]*mirror,transform[1],transform[2]*mirror,transform[3],transform[4]*mirror,transform[5]];
      return {...pngReference(texture),transform,source:"published",shadow:shadowValue(profile.pipelineShadow)};
    };
    try{return published();}catch{return builtin();}
  }
  function importFrames(payload) {
    const {profileId,label,action,files}=payload; if(!ID.test(profileId)||!ACTIONS.has(action)) throw Error("请选择有效角色ID与动作");
    if(!Array.isArray(files)||!files.length||files.length>120) throw Error("请选择1～120张PNG");
    const decoded=files.map(f=>{ if(typeof f.data!=="string"||!f.data.startsWith("data:image/png;base64,")) throw Error("仅支持PNG图片"); const bytes=Buffer.from(f.data.split(",")[1],"base64"); if(bytes.length>20*1024*1024) throw Error("单图不能超过20MB"); const info=pngInfo(bytes); if(!info.width||!info.height) throw Error("PNG损坏"); const hash=crypto.createHash("sha256").update(bytes).digest("hex"); return {bytes,info,name:path.basename(f.name||"frame.png"),relative:`workspace/projects/midnight/assets/${profileId}/${action}/${hash}.png`}; });
    const s=load(); let p=s.manifest.profiles.find(p=>p.id===profileId);
    if(!p){p={id:profileId,label:label||profileId,kind:"actor",bodyScale:1,runtimeScale:1,animations:[]};s.manifest.profiles.push(p);s.metadata.profiles[profileId]=defaults({id:profileId,sourceFacing:"left",targetRect:[-65,-145,130,155],poses:{}});}
    if(p.animations.some(a=>a.id===action)&&payload.replace!==true) throw Error("动作已存在，勾选替换后重试");
    const old=p.animations.find(a=>a.id===action); const anchor=old?.sourceAnchor||{x:decoded[0].info.width/2,y:decoded[0].info.height};
    const animation={id:action,name:action,anchorMode:"canvas_bottom_center",sourceAnchor:anchor,defaultScale:old?.defaultScale||.1,fps:8,loop:["idle","move"].includes(action),frames:decoded.map(d=>({name:d.name,path:d.relative,width:d.info.width,height:d.info.height,duration:1}))};
    for(const d of decoded){const full=asset(d.relative);fs.mkdirSync(path.dirname(full),{recursive:true});fs.writeFileSync(full,d.bytes);}
    p.animations=p.animations.filter(a=>a.id!==action);p.animations.push(animation);
    // Removed frames must not inherit another frame's tuning or audio on replacement.
    const prefix=`${profileId}/${action}:`; for(const key of Object.keys(s.tuning.frame_visual_overrides||{})) if(key.startsWith(prefix)) delete s.tuning.frame_visual_overrides[key];
    for(const group of ["frame_playback_overrides","frame_box_overrides"]) for(const key of Object.keys(s.tuning[group]||{})) if(key.startsWith(prefix)) delete s.tuning[group][key];
    const meta=s.metadata.profiles[profileId];for(const key of Object.keys(meta.frameAnchors||{})) if(key.startsWith(action+":")) delete meta.frameAnchors[key];
    for(const name of ["frame_audio_bindings.json","frame_image_attachments.json"]){const file=path.join(data,name);if(fs.existsSync(file))write(file,read(file,[]).filter(e=>!stableBindingKey(e).startsWith(prefix)));}
    const trailsFile=path.join(data,"attack_trails.json");if(fs.existsSync(trailsFile)){const trails=read(trailsFile);delete trails.bindings?.[`${profileId}/${action}`];write(trailsFile,trails);}
    save(s); return {ok:true,profileId,action,count:decoded.length};
  }
  function setMetadata(payload) {
    const s=load(),meta=s.metadata.profiles[payload.profileId];if(!meta)throw Error("角色不存在");
    const next=clone(meta);
    if(payload.targetEnemyIds!==undefined){const enemies=read(path.join(GAME,"data/enemies/enemies.json"));if(!Array.isArray(payload.targetEnemyIds)||payload.targetEnemyIds.some(id=>!Object.hasOwn(enemies,id)))throw Error("请选择现有游戏敌人");if(payload.profileId==="noren"&&payload.targetEnemyIds.length)throw Error("noren不绑定敌人");next.targetEnemyIds=[...new Set(payload.targetEnemyIds)];}
    if(payload.sourceFacing!==undefined){if(!["left","right"].includes(payload.sourceFacing))throw Error("无效朝向");next.visual.sourceFacing=payload.sourceFacing;}
    if(payload.targetRect!==undefined){const r=payload.targetRect;if(!Array.isArray(r)||r.length!==4)throw Error("目标区域需要X、Y、宽、高");next.visual.targetRect=[...vec(r.slice(0,2),"目标区域"),number(r[2],1,2000,"目标宽度"),number(r[3],1,2000,"目标高度")];}
    if(payload.attackStyle!==undefined){
      if(!STYLES.has(payload.attackStyle))throw Error("无效攻击类型");
      next.visual.attackStyleOverride=payload.attackStyle;
      next.attackStyleManual=true;
      delete next.attackStyleAuto;
    }
    if(payload.shadow){const x=payload.shadow;next.shadow={enabled:x.enabled===true,size:vec(x.size,"阴影尺寸").map(v=>number(v,0,500,"阴影尺寸")),offset:vec(x.offset,"阴影偏移"),opacity:number(x.opacity,0,1,"阴影透明度")};}
    if(payload.motion){const x=payload.motion;next.motion={speed:number(x.speed,100,8000,"移动速度"),reach:number(x.reach,10,400,"攻击距离"),windup:number(x.windup,0,3,"预备时长"),recovery:number(x.recovery,.01,3,"收招时长")};}
    if(payload.effects){const x=payload.effects;next.effects={scale:number(x.scale,0,5,"特效大小"),offset:vec(x.offset,"特效偏移")};}
    if(payload.laserMuzzle) next.visual.laserMuzzle=vec(payload.laserMuzzle,"掌心挂点");
    if(payload.laserPalmWidth!==undefined) next.visual.laserPalmWidth=number(payload.laserPalmWidth,1,1000,"掌宽");
    if(payload.attacks!==undefined) next.attacks=normalizeAttacks(payload.attacks);
    if(payload.anchor){const a=s.manifest.profiles.find(p=>p.id===payload.profileId).animations.find(a=>a.id===payload.action);if(!a)throw Error("动作不存在"); const xy=vec(payload.anchor,"脚底锚点"); if(payload.frameIndex!==undefined){number(payload.frameIndex,0,a.frames.length-1,"帧索引");next.frameAnchors[`${a.id}:${payload.frameIndex}`]=xy;a.frames[payload.frameIndex].anchor={x:xy[0],y:xy[1]};}else{a.sourceAnchor={x:xy[0],y:xy[1]};}}
    s.metadata.profiles[payload.profileId]=next;save(s);return {ok:true};
  }
  function importHitEffect(payload){
    const s=load(),meta=s.metadata.profiles[payload.profileId];if(!meta)throw Error("角色不存在");
    if(typeof payload.data!=="string"||!payload.data.startsWith("data:image/png;base64,"))throw Error("命中特效需要PNG");
    const bytes=Buffer.from(payload.data.split(",")[1],"base64");if(bytes.length>20*1024*1024)throw Error("图片不能超过20MB");const info=pngInfo(bytes);if(!info.width||!info.height)throw Error("PNG损坏");
    const hash=crypto.createHash("sha256").update(bytes).digest("hex"),relative=`workspace/projects/midnight/effects/${hash}.png`;
    fs.mkdirSync(path.dirname(asset(relative)),{recursive:true});fs.writeFileSync(asset(relative),bytes);meta.visual.hitEffectTexture=resource(asset(relative));save(s);return {ok:true,texture:meta.visual.hitEffectTexture};
  }
  function compile(profileIds) {
    const savedAudio=read(path.join(data,"frame_audio_bindings.json"),[]);
    const emptyLegacyAudio=savedAudio&&typeof savedAudio==="object"&&!Array.isArray(savedAudio)&&Object.keys(savedAudio).length===0;
    if(!Array.isArray(savedAudio)&&!emptyLegacyAudio)throw Error("帧音效绑定必须是数组，请检查 frame_audio_bindings.json");
    const audio=(emptyLegacyAudio?[]:savedAudio).map(entry=>{
      if(entry.path||entry.file)return {...entry,path:entry.path||entry.file};
      const match=/^data:audio\/([^;,]+);base64,([\s\S]+)$/.exec(entry.data||"");if(!match)throw Error("音频需要WAV、OGG或MP3数据");
      const ext={wav:".wav","x-wav":".wav",wave:".wav",mpeg:".mp3",mp3:".mp3",ogg:".ogg"}[match[1]];if(!ext)throw Error("不支持的音频格式 "+match[1]);
      const bytes=Buffer.from(match[2],"base64"),hash=crypto.createHash("sha256").update(bytes).digest("hex"),relative=`workspace/projects/midnight/audio/${hash}${ext}`;
      fs.mkdirSync(path.dirname(asset(relative)),{recursive:true});if(!fs.existsSync(asset(relative)))fs.writeFileSync(asset(relative),bytes);
      const copy={...entry,path:relative};delete copy.data;return copy;
    });
    const s=load(); const runtime=buildRuntimeData({manifest:s.manifest,tuning:s.tuning,projectId:"midnight",frameAudioBindings:audio,frameImageAttachments:read(path.join(data,"frame_image_attachments.json"),[]),attackTrails:read(path.join(data,"attack_trails.json"),{})});
    const result={schemaVersion:1,revision:revision(),profiles:{},bindings:{}};
    for(const p of runtime.profiles){
      if(profileIds?.length&&!profileIds.includes(p.id))continue;
      const meta=s.metadata.profiles[p.id];if(!meta)throw Error(`缺少角色配置 ${p.id}`);
      const visual=clone(meta.visual);visual.id=p.id;visual.poses={};visual.pipelineFrames={};visual.pipelineShadow=meta.shadow;visual.pipelineMotion=meta.motion;visual.pipelineEffects=meta.effects;
      visual.pipelineXsxb=resourcePaths(p);
      const authored=s.manifest.profiles.find(x=>x.id===p.id);
      for(const a of p.animations){
        if(!ACTIONS.has(a.id))throw Error(`不支持的动作 ${a.id}`);
        const original=authored.animations.find(x=>x.id===a.id);
        const frames=a.frames.filter(f=>!f.disabled).map(f=>{
          const full=asset(f.assetPath); if(!fs.existsSync(full))throw Error(`图片缺失 ${f.assetPath}`);
          const frameAnchor=original.frames[f.index].anchor;
          const anchor=frameAnchor?[frameAnchor.x,frameAnchor.y]:[a.sourceAnchor?.x??f.width/2,a.sourceAnchor?.y??f.height];
          const c=p.characterTransform,t=f.transform; const sx=c.scale.x*t.scale.x,sy=c.scale.y*t.scale.y;
          if(!Number.isFinite(sx)||!Number.isFinite(sy)||sx<=0||sy<=0)throw Error("缩放必须大于零");
          const r=(c.rotation+t.rotation)*Math.PI/180,co=Math.cos(r),si=Math.sin(r);
          const px=(c.position.x+t.position.x)*c.uniformScale+(f.width/2-anchor[0])*sx;
          const py=(c.position.y+t.position.y)*c.uniformScale+(f.height/2-anchor[1])*sy;
          const matrix=[co*sx,si*sx,-si*sy,co*sy,px-co*sx*f.width/2+si*sy*f.height/2,py-si*sx*f.width/2-co*sy*f.height/2];
          if(matrix.some(n=>!Number.isFinite(n)))throw Error("变换含无效数值");
          return {texture:resource(full),transform:matrix,duration:number(f.durationMs/1000,.000001,300,"帧时长"),loop:original.loop!==false,anchor,scale:sx,audio:f.audio.map(x=>x.path).filter(Boolean).map(x=>resource(asset(x))),attachments:resourcePaths(f.attachments),xsxb:resourcePaths(f)};
        });
        if(!frames.length)throw Error(`${a.id} 不能禁用全部帧`);
        visual.pipelineFrames[a.id]=frames;
        visual.poses[a.id]={...(meta.visual.poses[a.id]||{}),texture:frames[0].texture,anchor:frames[0].anchor,scale:frames[0].scale};
      }
      if(!visual.poses.idle)throw Error(`${p.label} 缺少idle`);
      if(visual.poseAliases) for(const key of Object.keys(visual.poseAliases)) if(!visual.poses[visual.poseAliases[key]])delete visual.poseAliases[key];
      let attackTemplates=null;
      if(meta.attacks!==undefined){
        attackTemplates=normalizeAttacks(meta.attacks);
        if(p.id!=="noren"&&Object.keys(attackTemplates).length>1&&!visual.attackStyleOverride&&!meta.attackStyleManual)
          throw Error(`${p.id} 有多个攻击模板，请先选择默认攻击方式；按招式分配时可人工确认“沿用默认动作”。`);
        validateAttackPoses(attackTemplates,visual.poses,visual.poseAliases);
        validateAttackResources(attackTemplates);
        visual.pipelineAttacks=attackTemplates;
      }
      const hasAuthoredTemplate=!!attackTemplates&&Object.hasOwn(attackTemplates,visual.attackStyleOverride);
      if(!hasAuthoredTemplate){
        const required={laser:["laser"],shoot:["shoot"],bite:["bite","bite_close"]}[visual.attackStyleOverride]||[];
        for(const action of required)if(!visual.poses[action])throw Error(`攻击方式需要 ${action}`);
        if(visual.attackStyleOverride==="laser"&&(!visual.laserMuzzle||!visual.laserPalmWidth))throw Error("射线需要掌心坐标与掌宽");
        if(visual.attackStyleOverride==="bite"&&!visual.hitEffectTexture)throw Error("旧咬击演出需要命中特效PNG；使用程序齿痕时请启用咬击模板。");
      }
      result.profiles[p.id]=visual;
      for(const enemyId of meta.targetEnemyIds||[]) {if(result.bindings[enemyId]&&result.bindings[enemyId]!==p.id)throw Error(`敌人 ${enemyId} 绑定冲突`);result.bindings[enemyId]=p.id;}
    }
    if(profileIds?.some(id=>!result.profiles[id]))throw Error("所选角色不存在");
    return result;
  }
  function preview(ids) {const catalog=compile(ids);write(previewFile,catalog);write(path.join(path.dirname(previewFile),"selection.json"),{profileId:ids?.[0]||Object.keys(catalog.profiles)[0],revision:catalog.revision});return {ok:true,revision:catalog.revision,profiles:Object.keys(catalog.profiles)};}
  function publish(ids) {
    if(!Array.isArray(ids)||!ids.length)throw Error("请选择要应用的角色");
    const catalog=compile(ids),previous=read(publishedFile,{schemaVersion:1,profiles:{},bindings:{}});
    // Freeze referenced media outside the ignored authoring tree for game exports.
    function freeze(value){
      if(Array.isArray(value))return value.map(freeze);
      if(value&&typeof value==="object")return Object.fromEntries(Object.entries(value).map(([k,v])=>[k,freeze(v)]));
      if(typeof value!=="string"||!value.startsWith("res://"))return value;
      const source=asset(value);if(!fs.existsSync(source)||!fs.statSync(source).isFile())throw Error(`发布资源缺失 ${value}`);
      const bytes=fs.readFileSync(source),hash=crypto.createHash("sha256").update(bytes).digest("hex");
      const target=path.join(path.dirname(publishedFile),"assets",hash+path.extname(source).toLowerCase());
      fs.mkdirSync(path.dirname(target),{recursive:true});if(!fs.existsSync(target))fs.writeFileSync(target,bytes);
      return resource(target);
    }
    const frozenProfiles=freeze(catalog.profiles);
    fs.mkdirSync(path.dirname(publishedFile),{recursive:true});
    const backupId=Date.now()+"-"+crypto.randomBytes(3).toString("hex");
    write(path.join(path.dirname(publishedFile),"backups",backupId+".json"),previous);
    const bindings={...previous.bindings};for(const [enemyId,profileId]of Object.entries(bindings))if(ids.includes(profileId))delete bindings[enemyId];Object.assign(bindings,catalog.bindings);
    write(publishedFile,{schemaVersion:1,revision:catalog.revision,profiles:{...previous.profiles,...frozenProfiles},bindings});
    return {ok:true,backupId,revision:catalog.revision,profiles:ids};
  }
  function rollback(backupId){if(!/^[0-9]+-[a-f0-9]{6}$/.test(backupId))throw Error("无效备份ID");const file=path.join(path.dirname(publishedFile),"backups",backupId+".json");if(!fs.existsSync(file))throw Error("备份不存在");const target=read(file);if(target.schemaVersion!==1||!target.profiles)throw Error("备份损坏");write(publishedFile,target);return {ok:true};}
  return {seed,status,scanAssets,load,save,importFrames,importHitEffect,setMetadata,compile,preview,publish,rollback,revision,norenReference,asset,workRoot,publishedFile,previewFile,scanReportFile,sourceRoot,data};
}
module.exports={createPipeline,ROOT,GAME,read,write,resource,ID,ACTIONS};
