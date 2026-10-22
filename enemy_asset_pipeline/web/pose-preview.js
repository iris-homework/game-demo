(function(root,factory){const api=factory();if(typeof module==="object"&&module.exports)module.exports=api;else root.MidnightPosePreview=api;})(typeof window!=="undefined"?window:this,function(){
  "use strict";
  function plan(actionId,idleId,activeFrameCount,holdMs=450,frameMs=125){
    if(activeFrameCount!==1||!idleId||/idle$/.test(actionId))return null;
    return [{id:idleId,duration:300},{id:actionId,duration:Math.max(50,Number(holdMs)||450,Number(frameMs)||0)},{id:idleId,duration:350}];
  }
  function sample(stages,elapsed){
    let start=0;
    for(let index=0;index<stages.length;index++){
      if(elapsed<start+stages[index].duration)return {index,time:Math.max(0,elapsed-start),complete:false};
      start+=stages[index].duration;
    }
    return {index:stages.length-1,time:stages.at(-1).duration,complete:true};
  }
  return {plan,sample};
});
