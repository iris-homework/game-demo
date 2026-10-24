"use strict";
const test=require("node:test"),assert=require("node:assert/strict"),fs=require("node:fs"),path=require("node:path");
const {characterNames,characterLabel,displayReport}=require("../character_names.cjs");
const {createPipeline,GAME,write}=require("../pipeline.cjs");

test("display names follow numbered asset directories with player and unillustrated labels",()=>{
 const names=characterNames();
 for(const [id,label]of Object.entries({warden_shield:"01a_warden_shield",robot:"02b_robot",gang_henchman:"03a_gang_henchman",fish:"12a_fish",noren:"noren",unillustrated:"无立绘"}))assert.equal(characterLabel(id,names),label);
 assert.equal(characterLabel("visual:warden_shield",names),"01a_warden_shield");
 assert.equal(characterLabel("Unillustrated",names),"无立绘");
 assert.ok(!Object.hasOwn(names,"reference_idle"));
 assert.equal(characterLabel("new_role",names),"new_role");
});

test("new role directories produce labels without a Chinese lookup table",t=>{
 const base=path.join(__dirname,"runtime");fs.mkdirSync(base,{recursive:true});const root=fs.mkdtempSync(path.join(base,"names-"));t.after(()=>fs.rmSync(root,{recursive:true,force:true}));
 for(const name of ["17a_new_guard","noren","reference_idle"])fs.mkdirSync(path.join(root,name));
 assert.deepEqual(characterNames(root),{noren:"noren",unillustrated:"无立绘",new_guard:"17a_new_guard"});
});

test("status and reports use canonical labels while preserving stored authoring and enemy ids",t=>{
 const base=path.join(__dirname,"runtime");fs.mkdirSync(base,{recursive:true});const root=fs.mkdtempSync(path.join(base,"name-status-"));t.after(()=>fs.rmSync(root,{recursive:true,force:true}));
 const pipeline=createPipeline({workRoot:root,publishedFile:path.join(root,"published.json"),previewFile:path.join(root,"preview.json")});
 const stored={manifest:{schemaVersion:1,profiles:[{id:"warden_shield",label:"巡界盾手",animations:[]},{id:"gang_henchman",label:"黑帮小弟",animations:[]}]},tuning:{values:{"keep":1.23}},metadata:{profiles:{warden_shield:{visual:{label:"巡界盾手"}},gang_henchman:{visual:{label:"黑帮小弟"}}}}};
 pipeline.save(stored);const before=JSON.stringify(pipeline.load());
 const report={addedProfiles:[{id:"warden_shield",label:"巡界盾手"}],warnings:[{code:"missingIdle",profileId:"warden_shield",message:"巡界盾手缺少待机"}]};write(pipeline.scanReportFile,report);
 const status=pipeline.status();assert.equal(status.profiles[0].label,"01a_warden_shield");assert.equal(status.profiles[1].label,"03a_gang_henchman");assert.deepEqual(status.profiles.map(p=>p.id),["warden_shield","gang_henchman"]);
 const enemies=JSON.parse(fs.readFileSync(path.join(GAME,"data/enemies/enemies.json"),"utf8"));assert.deepEqual(status.enemies.map(e=>e.id),Object.values(enemies).map(e=>e.id));
 assert.equal(status.enemies.find(e=>e.id==="ike").label,"无立绘");assert.equal(status.enemies.find(e=>e.id==="fish_second").label,"12a_fish");
 assert.equal(status.autoImport.addedProfiles[0].label,"01a_warden_shield");assert.ok(!status.autoImport.warnings[0].message.includes("巡界盾手"));
 assert.equal(JSON.stringify(pipeline.load()),before);assert.equal(report.addedProfiles[0].label,"巡界盾手");assert.equal(displayReport(report).addedProfiles[0].id,"warden_shield");
});
