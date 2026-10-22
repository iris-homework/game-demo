"use strict";
const http=require("node:http"),fs=require("node:fs"),path=require("node:path");
const {createPipeline,ROOT,GAME,read}=require("./pipeline.cjs");
const {characterLabel,displayReport}=require("./character_names.cjs");
const test=process.argv.includes("--test");
const port=Number(process.env.MIDNIGHT_PIPELINE_PORT||(test?5193:5191));
const nativePort=port+1;
const pipeline=createPipeline(test?{test:true,workRoot:path.join(ROOT,"test/session/authoring"),publishedFile:path.join(ROOT,"test/session/published/catalog.json"),previewFile:path.join(ROOT,"test/preview_catalog.json")}:{});
pipeline.seed();
process.env.PORT=String(nativePort);
process.env.MIDNIGHT_TUNER_ROOT=pipeline.workRoot;
process.env.MIDNIGHT_GAME_ROOT=GAME;
require("./vendor/xsxb/tools/animation_tuner/server.js");
const send=(res,code,value,type="application/json; charset=utf-8")=>{res.writeHead(code,{"content-type":type,"cache-control":"no-store","x-content-type-options":"nosniff"});res.end(typeof value==="string"||Buffer.isBuffer(value)?value:JSON.stringify(value));};
async function body(req){let size=0;const chunks=[];for await(const chunk of req){size+=chunk.length;if(size>160*1024*1024)throw Error("导入批次过大，请分批导入");chunks.push(chunk);}return JSON.parse(Buffer.concat(chunks).toString("utf8")||"{}");}
function proxy(req,res,url){const upstream=http.request({hostname:"127.0.0.1",port:nativePort,path:url,method:req.method,headers:{...req.headers,host:`127.0.0.1:${nativePort}`}},r=>{res.writeHead(r.statusCode,r.headers);r.pipe(res);});upstream.on("error",e=>send(res,502,{error:e.message}));req.pipe(upstream);}
const server=http.createServer(async(req,res)=>{
  try{
    const url=new URL(req.url,`http://127.0.0.1:${port}`);
    if(req.method==="POST"&&req.headers.origin&&!new Set([`http://127.0.0.1:${port}`,`http://localhost:${port}`]).has(req.headers.origin))return send(res,403,{error:"来源不允许"});
    if(url.pathname==="/pipeline/status")return send(res,200,{...pipeline.status(),port,upstream:read(path.join(ROOT,"upstream.json")),service:"midnight-enemy-pipeline"});
    if(req.method==="GET"&&url.pathname==="/pipeline/noren-reference")return send(res,200,pipeline.norenReference());
    if(url.pathname==="/pipeline/frames"){
      const s=pipeline.load(),p=s.manifest.profiles.find(p=>p.id===url.searchParams.get("id"));
      return send(res,200,{profile:p?{...p,label:characterLabel(p.id)}:p,metadata:s.metadata.profiles[p?.id]});
    }
    if(req.method==="POST"&&url.pathname.startsWith("/pipeline/")){
      const data=await body(req);
      const fn={"/pipeline/scan":()=>pipeline.scanAssets(),"/pipeline/import":()=>pipeline.importFrames(data),"/pipeline/hit-effect":()=>pipeline.importHitEffect(data),"/pipeline/metadata":()=>pipeline.setMetadata(data),"/pipeline/preview":()=>pipeline.preview(data.profileIds),"/pipeline/apply":()=>pipeline.publish(data.profileIds),"/pipeline/rollback":()=>pipeline.rollback(data.backupId)}[url.pathname];
      if(!fn)return send(res,404,{error:"接口不存在"});const result=fn();return send(res,200,url.pathname==="/pipeline/scan"?displayReport(result):result);
    }
    if(url.pathname==="/"||url.pathname.startsWith("/local/")){
      const relative=url.pathname==="/"?"index.html":url.pathname.slice(7);
      const full=path.resolve(ROOT,"web",relative);
      if(!full.startsWith(path.join(ROOT,"web")+path.sep)||!fs.existsSync(full))return send(res,404,"文件不存在","text/plain; charset=utf-8");
      const type={".html":"text/html",".css":"text/css",".js":"application/javascript"}[path.extname(full)]||"application/octet-stream";
      return send(res,200,fs.readFileSync(full),type+"; charset=utf-8");
    }
    if(url.pathname==="/tuner/"||url.pathname==="/tuner")return proxy(req,res,"/");
    if(url.pathname==="/api/projects"&&req.method==="POST")return send(res,403,{error:"当前工具固定绑定午夜委托制作项目"});
    return proxy(req,res,req.url);
  }catch(e){send(res,400,{error:e.message});}
});
server.listen(port,"127.0.0.1",()=>console.log(`MIDNIGHT_PIPELINE_READY http://127.0.0.1:${port} ${test?"TEST":"FORMAL"}`));
