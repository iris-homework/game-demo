"use strict";
const test=require("node:test"),assert=require("node:assert/strict"),fs=require("node:fs"),path=require("node:path");
const {createPipeline,GAME}=require("../pipeline.cjs");
const BUILTIN_TEXTURE="res://assets/combat_test/noren/noren_idle.png";

function fixture(t){
  const base=path.join(__dirname,"runtime");fs.mkdirSync(base,{recursive:true});
  const root=fs.mkdtempSync(path.join(base,"noren-reference-"));
  t.after(()=>fs.rmSync(root,{recursive:true,force:true}));
  const referenceFile=path.join(root,"formal/catalog.json");
  const pipeline=createPipeline({test:true,workRoot:path.join(root,"authoring"),publishedFile:path.join(root,"test-published/catalog.json"),previewFile:path.join(root,"preview.json"),referenceFile});
  return {root,referenceFile,pipeline};
}

function catalog({sourceFacing="left",pipelineFrames,poses,shadow}={}){
  const noren={id:"noren",sourceFacing,poses:poses||{idle:{texture:BUILTIN_TEXTURE,anchor:[710,1240],scale:.099}}};
  if(pipelineFrames!==undefined)noren.pipelineFrames=pipelineFrames;
  if(shadow!==undefined)noren.pipelineShadow=shadow;
  return {schemaVersion:1,profiles:{noren}};
}

function writeReference(file,value){
  fs.mkdirSync(path.dirname(file),{recursive:true});
  fs.writeFileSync(file,typeof value==="string"?value:JSON.stringify(value,null,2)+"\n");
}

function close(actual,expected,label){
  assert.equal(actual.length,expected.length,label);
  actual.forEach((value,index)=>assert.ok(Math.abs(value-expected[index])<1e-10,`${label}[${index}] expected ${expected[index]}, got ${value}`));
}

test("builtin noren reference keeps the game's fixed idle calibration and PNG alpha bounds",t=>{
  const {pipeline}=fixture(t),reference=pipeline.norenReference();
  assert.equal(reference.source,"builtin");
  assert.equal(reference.texture,BUILTIN_TEXTURE);
  assert.equal(reference.imageUrl,"/asset?path="+encodeURIComponent("game/assets/combat_test/noren/noren_idle.png"));
  close(reference.transform,[-.099,0,0,.099,70.29,-122.76],"transform");
  assert.deepEqual(reference.bounds,{x:110,y:58,width:1081,height:1176});
  assert.equal(reference.width,1224);assert.equal(reference.height,1285);
  assert.deepEqual(reference.shadow,{enabled:true,size:[32,9],offset:[0,2],opacity:.7});
  assert.ok(fs.existsSync(path.join(GAME,reference.texture.slice(6))));
});

test("formal published noren wins over test and authoring drafts",t=>{
  const {referenceFile,pipeline}=fixture(t);pipeline.seed();
  const draft=pipeline.load();draft.metadata.profiles.noren.visual.sourceFacing="right";draft.metadata.profiles.noren.shadow.opacity=.2;pipeline.save(draft);
  pipeline.preview(["noren"]);pipeline.publish(["noren"]);
  assert.equal(JSON.parse(fs.readFileSync(pipeline.publishedFile,"utf8")).profiles.noren.sourceFacing,"right");
  writeReference(referenceFile,catalog({
    sourceFacing:"left",
    pipelineFrames:{idle:[{texture:BUILTIN_TEXTURE,transform:[.2,.03,-.01,.21,8,-9]}]},
    shadow:{enabled:false,size:[40,11],offset:[-2,3],opacity:.4},
  }));
  const reference=pipeline.norenReference();
  assert.equal(reference.source,"published");
  close(reference.transform,[-.2,.03,.01,.21,-8,-9],"formal transform");
  assert.deepEqual(reference.shadow,{enabled:false,size:[40,11],offset:[-2,3],opacity:.4});
});

test("published frames and pose fallbacks mirror the X row exactly once toward the right",t=>{
  const {referenceFile,pipeline}=fixture(t);
  const frame={idle:[{texture:BUILTIN_TEXTURE,transform:[.1,.2,.3,.4,5,6]}]};
  writeReference(referenceFile,catalog({sourceFacing:"left",pipelineFrames:frame}));
  close(pipeline.norenReference().transform,[-.1,.2,-.3,.4,-5,6],"left frame");
  writeReference(referenceFile,catalog({sourceFacing:"right",pipelineFrames:frame}));
  close(pipeline.norenReference().transform,[.1,.2,.3,.4,5,6],"right frame");
  const poses={idle:{texture:BUILTIN_TEXTURE,anchor:[10,20],scale:.5}};
  writeReference(referenceFile,catalog({sourceFacing:"left",poses}));
  close(pipeline.norenReference().transform,[-.5,0,0,.5,5,-10],"left pose");
  writeReference(referenceFile,catalog({sourceFacing:"right",poses}));
  close(pipeline.norenReference().transform,[.5,0,0,.5,-5,-10],"right pose");
});

test("malformed published noren falls back to builtin calibration",t=>{
  const {referenceFile,pipeline}=fixture(t);
  writeReference(referenceFile,"{broken json");
  assert.equal(pipeline.norenReference().source,"builtin");
  writeReference(referenceFile,{...catalog(),schemaVersion:99});
  assert.equal(pipeline.norenReference().source,"builtin");
  writeReference(referenceFile,catalog({pipelineFrames:{idle:[{texture:BUILTIN_TEXTURE,transform:[1,2,3,4,5]}]}}));
  assert.equal(pipeline.norenReference().source,"builtin");
  writeReference(referenceFile,catalog({pipelineFrames:{idle:[{texture:BUILTIN_TEXTURE,transform:[1,0,0,1,0,0]}]},shadow:{enabled:true,size:[32,9],offset:[0,2],opacity:2}}));
  const reference=pipeline.norenReference();
  assert.equal(reference.source,"builtin");
  close(reference.transform,[-.099,0,0,.099,70.29,-122.76],"fallback transform");
});

test("published textures cannot traverse or leave the game directory",t=>{
  const {referenceFile,pipeline}=fixture(t);
  for(const texture of ["res://../README.md","res://assets/combat_test/noren/../../../../README.md","C:\\Windows\\win.ini","res://assets/combat_test/noren/noren_idle.txt"]){
    writeReference(referenceFile,catalog({pipelineFrames:{idle:[{texture,transform:[1,0,0,1,0,0]}]}}));
    const reference=pipeline.norenReference();
    assert.equal(reference.source,"builtin",texture);
    assert.equal(reference.texture,BUILTIN_TEXTURE,texture);
  }
});
