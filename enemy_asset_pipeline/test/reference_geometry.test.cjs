"use strict";
const test=require("node:test"),assert=require("node:assert/strict");
const {bounds,lineup,fit,point}=require("../web/noren-reference.js");
test("opaque bounds preserve actual game scale, mirror and canvas padding",()=>{
  const calibration=[-.099,0,0,.099,710*.099,-1240*.099];
  const soles=point(calibration,710,1240);assert.equal(soles.x,0);assert.equal(soles.y,0);
  const visible=bounds(calibration,{x:100,y:200,width:800,height:1000});
  assert.ok(Math.abs(visible.height-99)<1e-10);assert.ok(Math.abs(visible.width-79.2)<1e-10);
});
test("side by side uses one ground plane without rescaling either actor",()=>{
  const reference={x:-60,y:-140,width:120,height:140},enemy={x:-100,y:-210,width:200,height:210};
  const result=lineup(reference,enemy);assert.equal(result.referenceY,0);assert.equal(reference.height,140);assert.equal(enemy.height,210);
  assert.equal(enemy.x-(reference.x+result.referenceX+reference.width),36);
  for(const viewport of [[600,300],[250,150],[1400,900]]){
    const camera=fit(result.bounds,...viewport);
    const refPixels=reference.height*camera.zoom,enemyPixels=enemy.height*camera.zoom;
    assert.equal(enemyPixels/refPixels,1.5);
    assert.ok(result.bounds.x*camera.zoom+camera.x>=27.99);
    assert.ok((result.bounds.x+result.bounds.width)*camera.zoom+camera.x<=viewport[0]-27.99);
  }
});
test("rotation and nonuniform scale retain visible geometry for comparison",()=>{
  const rotated=bounds([0,2,-3,0,10,-20],{x:0,y:0,width:100,height:50});
  assert.deepEqual(rotated,{x:-140,y:-20,width:150,height:200});
});
test("oversized imports fit the reference and subject together",()=>{
  const result=lineup({x:-60,y:-140,width:120,height:140},{x:-5000,y:-9000,width:10000,height:9000});
  const camera=fit(result.bounds,600,300);
  assert.ok(camera.zoom>0&&camera.zoom<.12);
  assert.ok(result.bounds.y*camera.zoom+camera.y>=27.99);
  assert.ok((result.bounds.y+result.bounds.height)*camera.zoom+camera.y<=272.01);
});
