/* Shared geometry for the studio's same-depth reference. No asset mutations. */
(function(root,factory){const api=factory();if(typeof module==="object"&&module.exports)module.exports=api;else root.MidnightReference=api;})(typeof window!=="undefined"?window:this,function(){
  "use strict";
  function point(matrix,x,y){return {x:matrix[0]*x+matrix[2]*y+matrix[4],y:matrix[1]*x+matrix[3]*y+matrix[5]};}
  function bounds(matrix,rect){const corners=[[rect.x,rect.y],[rect.x+rect.width,rect.y],[rect.x,rect.y+rect.height],[rect.x+rect.width,rect.y+rect.height]].map(p=>point(matrix,...p));const xs=corners.map(p=>p.x),ys=corners.map(p=>p.y);return {x:Math.min(...xs),y:Math.min(...ys),width:Math.max(...xs)-Math.min(...xs),height:Math.max(...ys)-Math.min(...ys)};}
  function lineup(reference,subject,gap=36){const x=subject.x-gap-reference.x-reference.width;return {referenceX:x,referenceY:0,bounds:{x:Math.min(reference.x+x,subject.x),y:Math.min(reference.y,subject.y,0),width:Math.max(subject.x+subject.width,reference.x+x+reference.width)-Math.min(reference.x+x,subject.x),height:Math.max(reference.y+reference.height,subject.y+subject.height,12)-Math.min(reference.y,subject.y,0)}};}
  function fit(rect,width,height,padding=28){const availableW=Math.max(1,width-padding*2),availableH=Math.max(1,height-padding*2);const zoom=Math.min(8,availableW/Math.max(1,rect.width),availableH/Math.max(1,rect.height));return {zoom,x:width/2-(rect.x+rect.width/2)*zoom,y:height/2-(rect.y+rect.height/2)*zoom};}
  return {point,bounds,lineup,fit};
});
