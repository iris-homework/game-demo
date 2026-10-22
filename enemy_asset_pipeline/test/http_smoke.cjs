"use strict";
const assert=require("node:assert/strict"),fs=require("node:fs"),path=require("node:path"),crypto=require("node:crypto");
const {ROOT,GAME,createPipeline}=require("../pipeline.cjs");
const origin=process.env.PIPELINE_TEST_URL||"http://127.0.0.1:5193";
const formal=path.join(ROOT,"published/catalog.json"),before=fs.readFileSync(formal);
async function request(route,data){const response=await fetch(origin+"/pipeline/"+route,data?{method:"POST",headers:{"content-type":"application/json",origin},body:JSON.stringify(data)}:{});const result=await response.json();assert.equal(response.status,200,JSON.stringify(result));return result;}
(async()=>{
 const status=await request("status");assert.equal(status.test,true,"smoke runner must use the isolated server");
 const fixture=createPipeline({test:true,workRoot:path.join(ROOT,"test/session/authoring"),publishedFile:path.join(ROOT,"test/session/published/catalog.json"),previewFile:path.join(ROOT,"test/preview_catalog.json")});
 const source=fixture.load();source.tuning.values["profiles.gang_henchman.groups.idle.visual_size"]=.107;source.tuning.values["profiles.gang_henchman.groups.idle.visual_scale"]={x:.107,y:.107};fixture.save(source);
 await request("metadata",{profileId:"gang_henchman",shadow:{enabled:true,size:[36,10],offset:[0,2],opacity:.55},targetEnemyIds:["gang_henchman","gang_henchman_second"]});
 const preview=await request("preview",{profileIds:["gang_henchman"]});assert.ok(preview.revision);
 const previous=fs.existsSync(path.join(ROOT,"test/session/published/catalog.json"))?fs.readFileSync(path.join(ROOT,"test/session/published/catalog.json")):null;
 const applied=await request("apply",{profileIds:["gang_henchman"]});
 const catalog=JSON.parse(fs.readFileSync(path.join(ROOT,"test/session/published/catalog.json")));
 assert.equal(catalog.bindings.gang_henchman,"gang_henchman");
 assert.equal(catalog.profiles.gang_henchman.pipelineShadow.size[0],36);
 const texture=catalog.profiles.gang_henchman.pipelineFrames.idle[0].texture;
 assert.ok(texture.includes("test/session/published/assets/"));assert.ok(fs.existsSync(path.join(GAME,texture.slice(6))));
 await request("rollback",{backupId:applied.backupId});
 const restored=JSON.parse(fs.readFileSync(path.join(ROOT,"test/session/published/catalog.json")));
 assert.deepEqual(restored,previous?JSON.parse(previous):{schemaVersion:1,profiles:{},bindings:{}});
 assert.deepEqual(fs.readFileSync(formal),before,"test server cannot modify formal publication");
 console.log(JSON.stringify({ok:true,scope:"isolated HTTP metadata/preview/apply/media/rollback",revision:preview.revision,formalHash:crypto.createHash("sha256").update(before).digest("hex")},null,2));
})().catch(error=>{console.error(error);process.exitCode=1;});
