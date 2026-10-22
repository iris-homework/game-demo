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
    window: { addEventListener() {} }, localStorage: { getItem: () => "" },
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
        return { ok: true, json: async () => JSON.parse(JSON.stringify(result)) };
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
  return { pipeline, element, native, change, select };
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
