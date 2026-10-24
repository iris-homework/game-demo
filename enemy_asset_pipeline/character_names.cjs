"use strict";
const fs=require("node:fs"),path=require("node:path");
const {roleForDirectory}=require("./asset_discovery.cjs");
const DEFAULT_ROOT=path.resolve(__dirname,"../assets/combat_test");

function characterNames(root=DEFAULT_ROOT){
  const names={noren:"noren",unillustrated:"无立绘"};
  if(!fs.existsSync(root))return names;
  for(const entry of fs.readdirSync(root,{withFileTypes:true}).sort((a,b)=>a.name.localeCompare(b.name,"en"))){
    if(!entry.isDirectory()||entry.isSymbolicLink())continue;
    const id=roleForDirectory(entry.name);
    if(!id||id==="noren"||Object.hasOwn(names,id))continue;
    names[id]=entry.name.toLowerCase();
  }
  return names;
}
function characterLabel(id,names=characterNames()){
  const key=String(id||"").replace(/^visual:/,"").toLowerCase();
  return names[key]||key;
}
function displayReport(report,names=characterNames()){
  if(!report)return report;
  return {...report,addedProfiles:(report.addedProfiles||[]).map(p=>({...p,label:characterLabel(p.id,names)})),warnings:(report.warnings||[]).map(w=>w.code==="missingIdle"&&w.profileId?{...w,message:`${characterLabel(w.profileId,names)} 缺少 idle；已有动作可导入，但发布仍会被校验阻止`}:w)};
}
module.exports={characterNames,characterLabel,displayReport};
