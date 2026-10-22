"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const { createPipeline } = require("../pipeline.cjs");

// Execute the real page handlers against an isolated real metadata backend.
// Only DOM rendering and the embedded frame editor are replaced with doubles.
async function page(t) {
  const base = path.join(__dirname, "runtime");
  fs.mkdirSync(base, { recursive: true });
  const root = fs.mkdtempSync(path.join(base, "web-metadata-"));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const pipeline = createPipeline({ workRoot: path.join(root, "authoring"),
    publishedFile: path.join(root, "published.json"), previewFile: path.join(root, "preview.json"), test: true });
  pipeline.seed();
  const elements = new Map();
  const selectIds = new Set(["profile", "action", "frame", "targets", "import-action"]);
  const listeners = {};
  const transport = { pending: [], delayFrames: false };
  const native = { dirty: false, reloads: 0, loads: 0, selectedFrame: 0 };
  function element(id) {
    if (!elements.has(id)) elements.set(id, {
      id, value: "", checked: false, options: [], listeners: {}, naturalWidth: 0,
      get selectedOptions() { return this.options.filter(o => o.selected); },
      replaceChildren(...children) { this.options = children; if (selectIds.has(id)) this.value = String(children[0]?.value ?? ""); },
      addEventListener(event, fn) { this.listeners[event] = fn; },
      getBoundingClientRect() { return { width: 100, height: 100 }; },
    });
    return elements.get(id);
  }
  const tuner = element("tuner");
  tuner.contentDocument = { body: { classList: { contains: () => native.dirty } } };
  tuner.contentWindow = { document: { querySelector: () => null } };
  Object.defineProperty(tuner, "src", { set() { native.reloads++; } });
  const context = vm.createContext({
    document: { querySelector: s => element(s.slice(1)), querySelectorAll: () => [] },
    window: { addEventListener(type,fn) { listeners[type]=fn; }, location:{origin:"http://localhost"} }, localStorage: { getItem: () => "" },
    Option: function (text, value) { this.text = text; this.value = String(value); },
    MidnightAttackEditor: class {
      load(profile) { this.attacks = profile.attacks; native.loads++; }
      values() { return this.attacks; }
    },
    fetch: async (url, options) => {
      try {
        let result;
        if (url === "/pipeline/status") result = pipeline.status();
        else if (url.startsWith("/pipeline/frames?")) {
          const id = new URL(url, "http://localhost").searchParams.get("id");
          const data = pipeline.load();
          result = { profile: data.manifest.profiles.find(p => p.id === id), metadata: data.metadata.profiles[id] };
        } else if (url === "/pipeline/metadata") result = pipeline.setMetadata(JSON.parse(options.body));
        else throw Error("Unexpected request: " + url);
        const response = { ok: true, json: async () => JSON.parse(JSON.stringify(result)) };
        if (transport.delayFrames && url.startsWith("/pipeline/frames?")) return new Promise(resolve => transport.pending.push({url,resolve,response}));
        return response;
      } catch (error) { return { ok: false, json: async () => ({ error: error.message }) }; }
    },
  });
  vm.runInContext(fs.readFileSync(path.join(__dirname, "../web/app.js"), "utf8"), context);
  await new Promise(resolve => setImmediate(resolve));
  assert.match(element("message").textContent, /已载入/);
  const change = (id, value) => {
    element(id).value = String(value);
    element("calibration").listeners.change({ target: element(id) });
  };
  const select = async id => { element("profile").value = id; await element("profile").onchange(); };
  return { pipeline, element, native, change, select, transport, message:data=>listeners.message({source:tuner.contentWindow,origin:"http://localhost",data}) };
}

test("saved metadata survives A/B/A selection and resaving without reloading frame edits", async t => {
  const { pipeline, element, native, change, select } = await page(t);
  await select("robot");
  const values = { targetX: -81, targetY: -151, targetW: 173, targetH: 181,
    facing: "right", muzzleX: 13, muzzleY: -17, palm: 83, shadowW: 109, shadowH: 33,
    shadowX: 7, shadowY: -4, opacity: 0.37, speed: 1537, reach: 127, windup: 0.23,
    recovery: 0.41, "effect-scale": 1.7, effectX: 9, effectY: -11 };
  for (const [id, value] of Object.entries(values)) change(id, value);
  element("shadow-enabled").checked = false;
  for (const option of element("targets").options) option.selected = option.value === "fish";
  native.dirty = true;
  const loads = native.loads;
  await element("save-meta").onclick();
  assert.match(element("message").textContent, /演出草稿已保存/);
  const saved = pipeline.load().metadata.profiles.robot;
  assert.equal(saved.motion.speed, 1537);
  assert.deepEqual(saved.targetEnemyIds, ["fish"]);
  assert.equal(native.dirty, true);
  assert.equal(native.reloads, 0);
  assert.equal(native.loads, loads);
  await select("fish");
  assert.equal(element("profile").value, "robot", "unsaved frame edits still block switching");
  native.dirty = false;
  await select("fish");
  await select("robot");
  for (const [id, value] of Object.entries(values)) assert.equal(String(element(id).value), String(value), id);
  assert.equal(element("shadow-enabled").checked, false);
  assert.deepEqual(element("targets").selectedOptions.map(o => o.value), ["fish"]);
  await element("save-meta").onclick();
  assert.deepEqual(pipeline.load().metadata.profiles.robot, saved, "resave must not restore stale metadata");
});

test("failed metadata save keeps pending edits and prevents switching away", async t => {
  const { pipeline, element, change, select } = await page(t);
  await select("robot");
  const before = pipeline.load().metadata.profiles.robot;
  change("speed", -1);
  await element("save-meta").onclick();
  assert.doesNotMatch(element("message").textContent, /演出草稿已保存/);
  assert.deepEqual(pipeline.load().metadata.profiles.robot, before);
  await select("fish");
  assert.equal(element("profile").value, "robot");
  assert.equal(element("speed").value, "-1");
  assert.match(element("message").textContent, /左侧参数尚未保存/);
});

for (const order of [[0,1],[1,0]]) test(`overlapping role loads resolve ${order} without mixing frames or saved metadata`, async t => {
  const {pipeline,element,select,transport}=await page(t);
  const before=pipeline.load().metadata.profiles;
  transport.delayFrames=true;
  const a=select("robot"),b=select("fish");
  assert.equal(transport.pending.length,2);
  assert.equal(element("calibration").inert,true);
  assert.equal(element("tuner").inert,true);
  await element("save-meta").onclick();
  assert.match(element("message").textContent,/正在载入/);
  assert.deepEqual(pipeline.load().metadata.profiles,before,"save while loading cannot write old controls to new role");
  const requests=[a,b];
  for(const i of order){transport.pending[i].resolve(transport.pending[i].response);await requests[i];}
  assert.equal(element("profile").value,"fish");
  assert.equal(element("speed").value,before.fish.motion.speed);
  assert.equal(element("targetX").value,before.fish.visual.targetRect[0]);
  assert.equal(element("calibration").inert,false);
  assert.equal(element("tuner").inert,false);
  assert.equal(element("action").options[0].value,pipeline.load().manifest.profiles.find(p=>p.id==="fish").animations[0].id);
  await element("save-meta").onclick();
  const after=pipeline.load().metadata.profiles;
  assert.deepEqual(after.robot,before.robot,"obsolete reply cannot change robot");
  assert.deepEqual(after.fish.visual.targetRect,before.fish.visual.targetRect);
  assert.deepEqual(after.fish.motion,before.fish.motion);
  transport.delayFrames=false;
  await select("robot");
  assert.equal(element("targetX").value,before.robot.visual.targetRect[0]);
});

test("latest load failure restores the previous role and ignores an obsolete failure",async t=>{
  const {pipeline,element,select,transport}=await page(t);
  const previous=element("profile").value,before=pipeline.load().metadata.profiles;
  transport.delayFrames=true;
  const a=select("robot"),b=select("fish");
  transport.pending[1].resolve({ok:false,json:async()=>({error:"load failed"})});await b;
  assert.equal(element("profile").value,previous);
  assert.equal(element("calibration").inert,false);
  transport.pending[0].resolve({ok:false,json:async()=>({error:"obsolete failure"})});await a;
  assert.equal(element("message").textContent,"load failed");
  await element("save-meta").onclick();
  assert.deepEqual(pipeline.load().metadata.profiles.robot,before.robot);
  assert.deepEqual(pipeline.load().metadata.profiles.fish,before.fish);
});

test("late embedded-frame save refresh cannot overwrite a newly selected role",async t=>{
  const {pipeline,element,select,transport,message}=await page(t);
  await select("robot");
  transport.delayFrames=true;
  message({type:"midnight-saved"});
  const selection=select("fish");
  assert.equal(transport.pending.length,2);
  transport.pending[1].resolve(transport.pending[1].response);await selection;
  const image=element("foot-image").src,action=element("action").value;
  transport.pending[0].resolve(transport.pending[0].response);
  await new Promise(resolve=>setImmediate(resolve));
  assert.equal(element("profile").value,"fish");
  assert.equal(element("foot-image").src,image);
  assert.equal(element("action").value,action);
  assert.equal(element("targetX").value,pipeline.load().metadata.profiles.fish.visual.targetRect[0]);
});
