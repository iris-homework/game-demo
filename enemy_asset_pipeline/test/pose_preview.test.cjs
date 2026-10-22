"use strict";
const test=require("node:test"),assert=require("node:assert/strict");
const {plan,sample}=require("../web/pose-preview.js");
test("single pose actions start and finish at idle",()=>{
  for(const action of ["slash","pierce","move","block","damaged","bite","shoot","laser"]){
    const sequence=plan(action,"idle",1);assert.deepEqual(sequence.map(x=>x.id),["idle",action,"idle"]);
    assert.equal(sample(sequence,0).index,0);assert.equal(sample(sequence,300).index,1);
    assert.equal(sample(sequence,750).index,2);assert.equal(sample(sequence,1100).complete,true);
    assert.equal(sequence[sample(sequence,90000).index].id,"idle");
  }
});
test("idle itself and authored multi-frame animation keep their playback",()=>{
  assert.equal(plan("idle","idle",1),null);assert.equal(plan("gun_idle","gun_idle",1),null);
  assert.equal(plan("slash","idle",8),null);assert.equal(plan("slash","idle",0),null);
  assert.equal(plan("slash",null,1),null);
});
test("ranged stance and custom pose hold preserve the selected action",()=>{
  const ranged=plan("shoot","gun_idle",1,800,125);
  assert.deepEqual(ranged.map(x=>x.id),["gun_idle","shoot","gun_idle"]);
  assert.equal(sample(ranged,1099).index,1);assert.equal(sample(ranged,1100).index,2);
  assert.equal(plan("damaged","idle",1,100,2000)[1].duration,2000);
});
