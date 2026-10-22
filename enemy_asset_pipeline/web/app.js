"use strict";
const $=s=>document.querySelector(s);let state,profile,profileData,metaDirty=false,anchorDirty=false,shownAction="",shownFrame=0,pendingFiles=[],lastBackup=localStorage.getItem("midnightBackup")||"";
const labels={hit:"打击",idle:"待机",move:"移动",slash:"挥砍",pierce:"突刺／拳踢",block:"格挡",damaged:"受伤",shoot:"射击",laser:"掌心射线",bite:"张嘴",bite_close:"咬合",retreat:"后撤",gun_idle:"持枪待机",gun_block:"持枪格挡",gun_damaged:"持枪受伤",evade:"闪避",blunt:"钝击"};
const msg=t=>$("#message").textContent=t;
const characterName=id=>state?.characterNames?.[String(id).replace(/^visual:/,"").toLowerCase()]||String(id).replace(/^visual:/,"").toLowerCase();
function actionLabel(action){return action.name==="攻击"?"攻击":labels[action.id]||action.id;}
function renderScanReport(report){
 if(!report)return;
 const count=value=>Array.isArray(value)?value.length:Number(value)||0;
 $("#scan-summary").textContent=`扫描完成：新增 ${count(report.addedProfiles)} 个角色、${count(report.addedActions)} 个动作、${count(report.addedEffects)} 张特效。已有调参保留。`;
 const text=value=>typeof value==="string"?value:value?.message||JSON.stringify(value);
 const issues=(report.skipped||[]).filter(entry=>["invalidPng","outsideSourceRoot","unreadableFile","unreadableDirectory"].includes(entry.reason));
 const warnings=[...(report.warnings||[]).map(text),...issues.map(entry=>`${entry.file}：${entry.message}`),...(report.missingIdle||[]).map(value=>`${characterName(text(value))}：缺少 idle 待机图，补齐后才能发布。`)];
 $("#scan-details").hidden=!warnings.length;
 $("#scan-warnings").textContent=[...new Set(warnings)].join("\n");
}
function renderProfileNotes(){
 const missing=!profileData.profile.animations.some(a=>a.id==="idle");
 const note=$("#profile-source-note");note.hidden=!missing;
 note.textContent=missing?"当前角色缺少 idle 待机图。已有动作可校准，补齐待机后再预览、应用。":"";
 const texture=profile.visual.hitEffectTexture;
 if(texture&&profile.discoveredVfx?.texture===texture){$("#effect-file-name").textContent=`已识别 VFX：${texture.split("/").pop()}。多部件合图需另行拆分并配置挂件／拖尾；扫描不会自动播放整张合图。`;}
 else if(texture){$("#effect-file-name").textContent="命中特效："+texture.split("/").pop();}
}
async function api(endpoint,data){const res=await fetch("/pipeline/"+endpoint,data?{method:"POST",headers:{"content-type":"application/json"},body:JSON.stringify(data)}:{});const result=await res.json();if(!res.ok)throw Error(result.error||res.statusText);return result;}
function confirmAction(text){return new Promise(resolve=>{const dialog=$("#confirmation");$("#confirmation-text").textContent=text;$("#confirm-ok").onclick=()=>{dialog.close();resolve(true);};$("#confirm-cancel").onclick=()=>{dialog.close();resolve(false);};dialog.oncancel=()=>resolve(false);dialog.showModal();});}
function value(id,x){$("#"+id).value=x;}const num=id=>Number($("#"+id).value);
function dirty(){return $("#tuner").contentDocument?.body.classList.contains("hasUnsavedChanges");}
function requireSaved(allowAnchor=false){if(anchorDirty&&!allowAnchor)throw Error("脚底锚点尚未保存，请先点击保存本帧脚底。");if(metaDirty)throw Error("左侧参数尚未保存，请先点击保存演出草稿。");if(dirty())throw Error("右侧还有未保存的帧调整，请先点击右侧保存调参。");}
function syncCanvasShadow(){const api=$("#tuner").contentWindow.midnightCanvasPreview;if(!api||!profile)return;api.setShadow({enabled:$("#shadow-enabled").checked,size:[num("shadowW"),num("shadowH")],offset:[num("shadowX"),num("shadowY")],opacity:num("opacity")});}
function chooseNative(){const win=$("#tuner").contentWindow,select=win.document.querySelector("#profileSelect");if(!select||!profile)return;const apply=()=>{if(![...select.options].some(o=>o.value===profile.id))return false;if(select.value!==profile.id){select.value=profile.id;select.dispatchEvent(new win.Event("change",{bubbles:true}));}syncCanvasShadow();win.midnightSelectAction?.(profile.id,$("#action").value,num("frame"));return true;};if(!apply()){const observer=new MutationObserver(()=>{if(apply())observer.disconnect();});observer.observe(select,{childList:true,subtree:true});}}
async function refresh(preferred){state=await api("status");const pick=$("#profile");pick.replaceChildren(...state.profiles.map(p=>new Option(p.label,p.id)));pick.value=preferred||profile?.id||"gang_henchman";if(!pick.value)pick.selectedIndex=0;$("#mode").textContent=state.test?"测试版 · 应用到隔离目录":"正式版";await selectProfile();}
async function selectProfile(){profile=state.profiles.find(p=>p.id===$("#profile").value);if(!profile)return;profileData=await api("frames?id="+encodeURIComponent(profile.id));
// The frames response owns the latest saved metadata. The status list may
// predate a save; merge here before filling controls, without reloading the tuner.
Object.assign(profile,profileData.metadata);
$("#action").replaceChildren(...profileData.profile.animations.map(a=>new Option(actionLabel(a),a.id)));$("#targets").replaceChildren(...state.enemies.map(e=>{const option=new Option(e.label,e.id);option.title=e.id;option.selected=(profile.targetEnemyIds||[]).includes(e.id);return option;}));$("#targets").disabled=profile.id==="noren";metaDirty=false;value("import-id",profile.id);value("import-label",characterName(profile.id));value("facing",profile.visual.sourceFacing||"left");value("attack",profile.visual.attackStyleOverride||"");value("muzzleX",profile.visual.laserMuzzle?.[0]||0);value("muzzleY",profile.visual.laserMuzzle?.[1]||0);value("palm",profile.visual.laserPalmWidth||70);$("#shadow-enabled").checked=profile.shadow.enabled;for(const [id,x]of Object.entries({targetX:profile.visual.targetRect[0],targetY:profile.visual.targetRect[1],targetW:profile.visual.targetRect[2],targetH:profile.visual.targetRect[3],shadowW:profile.shadow.size[0],shadowH:profile.shadow.size[1],shadowX:profile.shadow.offset[0],shadowY:profile.shadow.offset[1],opacity:profile.shadow.opacity,...profile.motion,"effect-scale":profile.effects.scale,effectX:profile.effects.offset[0],effectY:profile.effects.offset[1]}))value(id,x);$("#effect-file-name").textContent=profile.visual.hitEffectTexture?"已绑定命中特效PNG":"尚未绑定图片（模板可使用程序特效）";attackPointPicking=false;attackEditor.load(profile,profileData.profile.animations);$("#attack").disabled=profile.id==="noren";selectAction();chooseNative();syncCanvasShadow();msg("已载入 "+profile.label+"。帧编辑保存在右侧，战场参数保存在左侧。");}
function selectAction(sync=true){renderProfileNotes();const a=profileData.profile.animations.find(a=>a.id===$("#action").value);$("#frame").replaceChildren(...a.frames.map((f,i)=>new Option(`${i+1} · ${f.name}`,i)));selectFrame(sync);}
function selectFrame(sync=true){anchorDirty=false;shownAction=$("#action").value;shownFrame=num("frame");const a=profileData.profile.animations.find(a=>a.id===$("#action").value),i=num("frame"),f=a.frames[i];const anchor=f.anchor?[f.anchor.x,f.anchor.y]:[a.sourceAnchor?.x??f.width/2,a.sourceAnchor?.y??f.height];$("#foot-image").src="/asset?path="+encodeURIComponent(f.path);value("anchorX",anchor[0]);value("anchorY",anchor[1]);drawCross();if(sync)$("#tuner").contentWindow.midnightSelectAction?.(profile.id,a.id,i);}
function drawCross(){const img=$("#foot-image"),box=img.getBoundingClientRect();if(!img.naturalWidth)return;const scale=Math.min(box.width/img.naturalWidth,box.height/img.naturalHeight);const left=(box.width-img.naturalWidth*scale)/2,top=(box.height-img.naturalHeight*scale)/2;$("#cross").style.left=left+num("anchorX")*scale+"px";$("#cross").style.top=top+num("anchorY")*scale+"px";}
$("#foot-image").onload=drawCross;$("#foot-editor").onclick=e=>{const img=$("#foot-image"),rect=img.getBoundingClientRect(),scale=Math.min(rect.width/img.naturalWidth,rect.height/img.naturalHeight);const x=(e.clientX-rect.left-(rect.width-img.naturalWidth*scale)/2)/scale,y=(e.clientY-rect.top-(rect.height-img.naturalHeight*scale)/2)/scale;if(attackPointPicking){attackPointPicking=false;attackEditor.setMuzzle(Math.round(x),Math.round(y));msg("攻击点已标记，请保存演出草稿。脚底锚点未改变。");return;}value("anchorX",Math.round(Math.max(0,Math.min(img.naturalWidth,x))));value("anchorY",Math.round(Math.max(0,Math.min(img.naturalHeight,y))));anchorDirty=true;drawCross();};
$("#profile").onchange=()=>run(async()=>{try{requireSaved();}catch(e){$("#profile").value=profile.id;throw e;}await selectProfile();});$("#action").onchange=()=>run(async()=>{if(anchorDirty){$("#action").value=shownAction;throw Error("先保存本帧脚底，再切换动作。");}selectAction();});$("#frame").onchange=()=>run(async()=>{if(anchorDirty){$("#frame").value=shownFrame;throw Error("先保存本帧脚底，再切换帧。");}selectFrame();});$("#anchorX").oninput=$("#anchorY").oninput=()=>{anchorDirty=true;drawCross();};
async function run(fn){try{await fn();}catch(e){msg(e.message);}}
function reloadNative(){ $("#tuner").src="/tuner/?rev="+Date.now(); }
$("#scan-assets").onclick=()=>run(async()=>{
 requireSaved();const button=$("#scan-assets"),selected=profile?.id;button.disabled=true;button.textContent="正在扫描…";
 try{const report=await api("scan",{});renderScanReport(report);if(report.ok===false)throw Error("扫描未完成，请查看素材扫描提示。");await refresh(selected);renderScanReport(report);if((report.addedProfiles?.length||0)+(report.addedActions?.length||0)+(report.addedEffects?.length||0))reloadNative();msg("素材扫描完成。新增内容已进入制作草稿，调整后再送入战斗预览。");}
 finally{button.disabled=false;button.textContent="扫描新增PNG";}
});
$("#tuner").onload=()=>{try{const doc=$("#tuner").contentDocument;const css=doc.createElement("link");css.rel="stylesheet";css.href="/local/native.css";doc.head.append(css);doc.querySelector("h1").textContent="午夜委托 · 帧编辑";doc.querySelector("#updatePanel")?.remove();for(const s of [".projectActions",".languageField","#projectBinding","#boxSection"]){const el=doc.querySelector(s);if(el)el.style.display="none";}chooseNative();}catch{}};
$("#save-anchor").onclick=()=>run(async()=>{requireSaved(true);await api("metadata",{profileId:profile.id,action:$("#action").value,frameIndex:num("frame"),anchor:[num("anchorX"),num("anchorY")]});reloadNative();await refresh(profile.id);msg("本帧脚底已保存；可在右侧检查对齐。");});
$("#save-meta").onclick=()=>run(async()=>{await api("metadata",{profileId:profile.id,targetRect:[num("targetX"),num("targetY"),num("targetW"),num("targetH")],targetEnemyIds:[...$("#targets").selectedOptions].map(o=>o.value),sourceFacing:$("#facing").value,attackStyle:$("#attack").value,attacks:attackEditor.values(),laserMuzzle:[num("muzzleX"),num("muzzleY")],laserPalmWidth:num("palm"),shadow:{enabled:$("#shadow-enabled").checked,size:[num("shadowW"),num("shadowH")],offset:[num("shadowX"),num("shadowY")],opacity:num("opacity")},motion:{speed:num("speed"),reach:num("reach"),windup:num("windup"),recovery:num("recovery")},effects:{scale:num("effect-scale"),offset:[num("effectX"),num("effectY")]}});profile.attacks=attackEditor.values();profile.visual.attackStyleOverride=$("#attack").value;metaDirty=false;msg("演出草稿已保存。右侧尚未保存的帧调整可继续编辑。");});
$("#preview").onclick=()=>run(async()=>{requireSaved();const r=await api("preview",{profileIds:[profile.id]});msg(`预览已准备：${profile.label}\n回到Godot测试台，点击「刷新草稿」。版本 ${r.revision}`);});
$("#apply").onclick=()=>run(async()=>{requireSaved();if(!await confirmAction(`应用「${profile.label}」的已保存配置？${state.test?"本次只写入测试目录。":"新建战斗将读取新版本。"}`))return;const r=await api("apply",{profileIds:[profile.id]});lastBackup=r.backupId;localStorage.setItem("midnightBackup",lastBackup);$("#tuner").contentWindow.midnightCanvasPreview?.refreshReference();msg("已应用 "+profile.label+"。如需恢复，可点击撤回上次应用。");});
$("#rollback").onclick=()=>run(async()=>{if(!lastBackup)throw Error("本浏览器尚无应用记录");if(!await confirmAction("恢复上次应用前的正式配置？"))return;await api("rollback",{backupId:lastBackup});$("#tuner").contentWindow.midnightCanvasPreview?.refreshReference();msg("已恢复上一版配置。");});
document.querySelectorAll("[data-page]").forEach(b=>b.onclick=()=>{document.querySelectorAll("[data-page]").forEach(x=>x.classList.toggle("selected",x===b));$("#calibration").hidden=b.dataset.page!=="calibration";$("#import").hidden=b.dataset.page!=="import";});
$("#import-action").replaceChildren(...Object.entries(labels).map(([id,label])=>new Option(label,id)));
function showFiles(){const list=$("#file-order");list.replaceChildren();pendingFiles.forEach((file,i)=>{const li=document.createElement("li");li.textContent=file.name;for(const [text,delta]of [["↑",-1],["↓",1]]){const b=document.createElement("button");b.textContent=text;b.onclick=()=>{const j=i+delta;if(j<0||j>=pendingFiles.length)return;[pendingFiles[i],pendingFiles[j]]=[pendingFiles[j],pendingFiles[i]];showFiles();};li.append(b);}list.append(li);});}
$("#import-id").oninput=()=>value("import-label",characterName($("#import-id").value.trim()));
$("#files").onchange=()=>{pendingFiles=[...$("#files").files];showFiles();};
$("#import-files").onclick=()=>run(async()=>{requireSaved();if(!pendingFiles.length)throw Error("请先选择PNG");const files=await Promise.all(pendingFiles.map(file=>new Promise((resolve,reject)=>{const r=new FileReader();r.onload=()=>resolve({name:file.name,data:r.result});r.onerror=reject;r.readAsDataURL(file);})));const r=await api("import",{profileId:$("#import-id").value.trim(),label:$("#import-label").value.trim(),action:$("#import-action").value,replace:$("#replace").checked,files});reloadNative();await refresh(r.profileId);msg(`已导入 ${r.count} 张PNG，进入右侧调整大小与时长。`);});
let attackPointPicking=false;
const attackEditor=new MidnightAttackEditor($("#attack-editor"),()=>{metaDirty=true;});
$("#attack").addEventListener("change",()=>{const key=$("#attack").value;if(key)attackEditor.select(key,true);});
$("#use-bound-impact").onclick=()=>{const path=profile.visual.hitEffectTexture;if(!path){msg("请先在战斗特效中导入命中特效PNG。");return;}attackEditor.field("impactTexture").value=path;attackEditor.capture();metaDirty=true;msg("命中特效已绑定到当前动作；请确认图片为单张特效并保存演出草稿。");};
$("#pick-attack-point").onclick=()=>{attackPointPicking=true;msg("请在上方当前帧图片中点击嘴部、武器接触处或发射口；这次点击只标记攻击点。");};
$("#calibration").addEventListener("input",e=>{if(["shadow-enabled","shadowW","shadowH","shadowX","shadowY","opacity"].includes(e.target.id))syncCanvasShadow();});
$("#calibration").addEventListener("change",e=>{if(!["action","frame","anchorX","anchorY","hit-effect-file","attack-template"].includes(e.target.id))metaDirty=true;});window.addEventListener("resize",drawCross);run(async()=>{await refresh();renderScanReport(state.autoImport);});

$("#import-hit-effect").onclick=()=>run(async()=>{requireSaved();const file=$("#hit-effect-file").files[0];if(!file)throw Error("请选择命中特效PNG");const data=await new Promise((resolve,reject)=>{const reader=new FileReader();reader.onload=()=>resolve(reader.result);reader.onerror=reject;reader.readAsDataURL(file);});const result=await api("hit-effect",{profileId:profile.id,data});profile.visual.hitEffectTexture=result.texture;msg("命中特效PNG已保存，送入预览可检查大小与位置。");$("#effect-file-name").textContent=file.name;});

window.addEventListener("message",event=>{
 if(event.source!==$("#tuner").contentWindow||event.origin!==window.location.origin||!profile)return;
 const data=event.data;
 if(data?.type==="midnight-selection"&&data.profileId===profile.id){
   if(anchorDirty){msg("脚底锚点尚未保存；先保存后再切换帧。");return;}
   if(!profileData.profile.animations.some(a=>a.id===data.actionId))return;
   if($("#action").value!==data.actionId){$("#action").value=data.actionId;selectAction(false);}
   if([...$("#frame").options].some(o=>Number(o.value)===data.frameIndex)){$("#frame").value=data.frameIndex;selectFrame(false);}
 }
 if(data?.type==="midnight-saved"&&!anchorDirty)run(async()=>{
   const selectedAction=$("#action").value,selectedIndex=num("frame");
   profileData=await api("frames?id="+encodeURIComponent(profile.id));
   $("#action").replaceChildren(...profileData.profile.animations.map(a=>new Option(actionLabel(a),a.id)));
   if([...$("#action").options].some(o=>o.value===selectedAction))$("#action").value=selectedAction;
   attackEditor.animations=profileData.profile.animations;attackEditor.render();selectAction(false);$("#frame").selectedIndex=Math.min(selectedIndex,$("#frame").options.length-1);selectFrame(false);
 });
});
