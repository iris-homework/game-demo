"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const zlib = require("node:zlib");
const { createPipeline, GAME, ACTIONS, read, write } = require("../pipeline.cjs");
const { opaqueBoundsForPng } = require("../vendor/xsxb/tools/box_estimator");
const { pathInside, roleForDirectory } = require("../asset_discovery.cjs");

const CRC_TABLE = (() => {
  const table = new Uint32Array(256);
  for (let value = 0; value < 256; value += 1) {
    let current = value;
    for (let bit = 0; bit < 8; bit += 1) current = current & 1 ? 0xedb88320 ^ (current >>> 1) : current >>> 1;
    table[value] = current >>> 0;
  }
  return table;
})();

function crc32(buffer) {
  let current = 0xffffffff;
  for (const byte of buffer) current = CRC_TABLE[(current ^ byte) & 0xff] ^ (current >>> 8);
  return (current ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const name = Buffer.from(type, "ascii");
  const result = Buffer.alloc(data.length + 12);
  result.writeUInt32BE(data.length, 0);
  name.copy(result, 4);
  data.copy(result, 8);
  result.writeUInt32BE(crc32(Buffer.concat([name, data])), data.length + 8);
  return result;
}

function pngBuffer(options = {}) {
  const width = options.width || 240;
  const height = options.height || 400;
  const rect = options.rect || { x: 60, y: 80, width: 100, height: 260 };
  const rowBytes = width * 4;
  const raw = Buffer.alloc((rowBytes + 1) * height);
  for (let y = 0; y < height; y += 1) {
    raw[y * (rowBytes + 1)] = 0;
    for (let x = 0; x < width; x += 1) {
      if (x < rect.x || y < rect.y || x >= rect.x + rect.width || y >= rect.y + rect.height) continue;
      const offset = y * (rowBytes + 1) + 1 + x * 4;
      raw[offset] = 210;
      raw[offset + 1] = 220;
      raw[offset + 2] = 230;
      raw[offset + 3] = 255;
    }
  }
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width, 0);
  header.writeUInt32BE(height, 4);
  header[8] = 8;
  header[9] = 6;
  header[10] = 0;
  header[11] = 0;
  header[12] = 0;
  return Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    chunk("IHDR", header),
    chunk("IDAT", zlib.deflateSync(raw)),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}

function makePipeline(t, options = {}) {
  const base = path.join(__dirname, "runtime");
  fs.mkdirSync(base, { recursive: true });
  const root = fs.mkdtempSync(path.join(base, "discovery-"));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const sourceRoot = options.sourceRoot || path.join(root, "source/combat_test");
  fs.mkdirSync(sourceRoot, { recursive: true });
  const pipelineOptions = {
    workRoot: path.join(root, "authoring"),
    publishedFile: path.join(root, "published/catalog.json"),
    previewFile: path.join(root, "preview.json"),
    sourceRoot,
    test: true,
  };
  const pipeline = createPipeline(pipelineOptions);
  if (options.seed !== false) pipeline.seed();
  return { root, sourceRoot, pipeline, pipelineOptions };
}

function writePng(sourceRoot, directory, fileName, options = {}) {
  const full = path.join(sourceRoot, directory, fileName);
  fs.mkdirSync(path.dirname(full), { recursive: true });
  fs.writeFileSync(full, options.bytes ? options.bytes : pngBuffer(options));
  return full;
}

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function profileOf(pipeline, id) {
  return pipeline.load().manifest.profiles.find((profile) => profile.id === id);
}

function actionIds(profile) {
  return profile.animations.map((animation) => animation.id);
}

test("discovery maps attack to pierce, appends actions, estimates anchors and keeps manual values", (t) => {
  const { sourceRoot, pipeline } = makePipeline(t);
  const initial = pipeline.load();
  initial.tuning.values["profiles.warden_shield.groups.idle.visual_size"] = 0.2;
  initial.tuning.frame_visual_overrides["warden_shield/idle:0"] = { visual_size: 1.5 };
  pipeline.save(initial);
  pipeline.setMetadata({
    profileId: "warden_shield",
    motion: { speed: 1234, reach: 95, windup: 0.1, recovery: 0.2 },
    effects: { scale: 1.25, offset: [3, 4] },
  });
  const before = pipeline.load();
  const idleBefore = clone(profileOf(pipeline, "warden_shield").animations.find((animation) => animation.id === "idle"));
  const metadataBefore = clone(before.metadata.profiles.warden_shield);
  const tuningFile = path.join(pipeline.data, "animation_tuning.json");
  const manifestFile = path.join(pipeline.data, "animation_manifest.json");
  const metadataFile = path.join(pipeline.data, "midnight.json");
  const tuningBefore = fs.readFileSync(tuningFile, "utf8");
  const fixedTime = new Date("2020-01-01T00:00:00Z");
  fs.utimesSync(tuningFile, fixedTime, fixedTime);
  const bindings = [{ metadata: { profileId: "warden_shield", animation: "idle", frame: 0 }, path: "manual.wav" }];
  write(path.join(pipeline.data, "frame_audio_bindings.json"), bindings);

  writePng(sourceRoot, "01a_warden_shield", "warden_shield_idle.png", { width: 300, height: 500 });
  writePng(sourceRoot, "01a_warden_shield", "warden_shield_move.png", {
    width: 300,
    height: 600,
    rect: { x: 100, y: 120, width: 80, height: 400 },
  });
  writePng(sourceRoot, "01a_warden_shield", "warden_shield_attack.png", { width: 260, height: 430 });
  writePng(sourceRoot, "01a_warden_shield", "warden_shield_damaged.png", { width: 250, height: 420 });
  writePng(sourceRoot, "01a_warden_shield", "warden_shield_VFX.png", { width: 320, height: 180 });

  const report = pipeline.scanAssets();
  assert.equal(report.ok, true);
  assert.deepEqual(report.addedActions.map((entry) => entry.action), ["move", "pierce", "damaged"]);
  const attack = report.addedActions.find((entry) => entry.action === "pierce");
  assert.equal(attack.mappedFrom, "attack");
  assert.equal(attack.name, "攻击");
  assert.equal(ACTIONS.has("attack"), false);
  assert.equal(report.addedEffects.length, 1);
  assert.equal(report.addedProfiles.length, 0);
  assert.ok(report.skipped.some((entry) => entry.file.endsWith("warden_shield_idle.png") && entry.reason === "actionExists"));

  const after = pipeline.load();
  const profile = after.manifest.profiles.find((entry) => entry.id === "warden_shield");
  assert.deepEqual(profile.animations[0], idleBefore);
  assert.deepEqual(actionIds(profile), ["idle", "move", "pierce", "damaged"]);
  assert.equal(profile.animations.find((animation) => animation.id === "pierce").name, "攻击");
  assert.ok(!profile.animations.some((animation) => animation.id === "attack"));

  const move = profile.animations.find((animation) => animation.id === "move");
  const moveBounds = opaqueBoundsForPng(path.join(sourceRoot, "01a_warden_shield", "warden_shield_move.png"));
  assert.deepEqual(move.sourceAnchor, { x: moveBounds.x + moveBounds.width / 2, y: moveBounds.y + moveBounds.height });
  const idleBounds = opaqueBoundsForPng(pipeline.asset(idleBefore.frames[0].path));
  assert.ok(Math.abs(move.defaultScale - 1.5 * idleBounds.height / moveBounds.height) < 0.00001);
  assert.ok(fs.existsSync(pipeline.asset(move.frames[0].path)));
  assert.deepEqual(
    fs.readFileSync(pipeline.asset(move.frames[0].path)),
    fs.readFileSync(path.join(sourceRoot, "01a_warden_shield", "warden_shield_move.png")),
  );

  assert.deepEqual(after.metadata.profiles.warden_shield.motion, metadataBefore.motion);
  assert.deepEqual(after.metadata.profiles.warden_shield.effects, metadataBefore.effects);
  assert.ok(fs.existsSync(pipeline.asset(after.metadata.profiles.warden_shield.visual.hitEffectTexture)));
  assert.ok(after.metadata.profiles.warden_shield.discoveredVfx.source.endsWith("warden_shield_VFX.png"));
  assert.equal(after.metadata.profiles.warden_shield.discoveredVfx.status, "pending-calibration");
  assert.equal(fs.readFileSync(tuningFile, "utf8"), tuningBefore);
  assert.ok(Math.abs(fs.statSync(tuningFile).mtimeMs - fixedTime.getTime()) < 2);
  assert.deepEqual(read(path.join(pipeline.data, "frame_audio_bindings.json")), bindings);
  assert.equal(pipeline.status().autoImport.addedActions.length, 3);
  assert.equal(pipeline.status().autoImportReport, "data/projects/midnight/asset_scan_report.json");

  const manifestBeforeSecondScan = fs.readFileSync(manifestFile, "utf8");
  const metadataBeforeSecondScan = fs.readFileSync(metadataFile, "utf8");
  const second = pipeline.scanAssets();
  assert.equal(second.unchanged, true);
  assert.deepEqual(second.addedProfiles, []);
  assert.deepEqual(second.addedActions, []);
  assert.deepEqual(second.addedEffects, []);
  assert.equal(fs.readFileSync(manifestFile, "utf8"), manifestBeforeSecondScan);
  assert.equal(fs.readFileSync(metadataFile, "utf8"), metadataBeforeSecondScan);
  assert.equal(fs.readFileSync(tuningFile, "utf8"), tuningBefore);
  assert.ok(second.skipped.some((entry) => entry.reason === "existingHitEffectTexture"));
  assert.equal(second.revision, pipeline.revision());
});

test("discovery never replaces existing or manually configured actions", (t) => {
  const { sourceRoot, pipeline } = makePipeline(t);
  const state = pipeline.load();
  const gang = state.manifest.profiles.find((profile) => profile.id === "gang_boss");
  gang.animations.push({
    id: "slash",
    name: "手工斩",
    anchorMode: "canvas_bottom_center",
    sourceAnchor: { x: 11, y: 22 },
    defaultScale: 0.33,
    fps: 5,
    loop: false,
    frames: [{ name: "manual.png", path: "game/assets/combat_test/03b_gang_boss/gang_boss_pierce.png", width: 1, height: 1, duration: 1 }],
  });
  state.metadata.profiles.gang_boss.visual.poses.slash = {
    texture: "res://assets/combat_test/03b_gang_boss/gang_boss_pierce.png",
    anchor: [11, 22],
    scale: 0.33,
  };
  state.metadata.profiles.gang_boss.frameAnchors["slash:0"] = [4, 5];
  state.tuning.values["profiles.gang_boss.groups.pierce.visual_size"] = 0.333;
  pipeline.save(state);
  const before = clone(state.manifest.profiles.find((profile) => profile.id === "gang_boss"));
  const tuningFile = path.join(pipeline.data, "animation_tuning.json");
  const manifestFile = path.join(pipeline.data, "animation_manifest.json");
  const tuningBefore = fs.readFileSync(tuningFile, "utf8");
  const manifestBefore = fs.readFileSync(manifestFile, "utf8");

  writePng(sourceRoot, "03b_gang_boss", "gang_boss_attack.png", { width: 220, height: 360 });
  writePng(sourceRoot, "03b_gang_boss", "gang_boss_slash.png", { width: 220, height: 360 });
  writePng(sourceRoot, "03b_gang_boss", "gang_boss_move.png", { width: 220, height: 360 });

  const report = pipeline.scanAssets();
  assert.deepEqual(profileOf(pipeline, "gang_boss"), before);
  assert.equal(report.addedActions.length, 0);
  assert.equal(report.unchanged, true);
  assert.ok(report.skipped.some((entry) => entry.file.endsWith("gang_boss_attack.png") && entry.reason === "actionExists"));
  assert.ok(report.skipped.some((entry) => entry.file.endsWith("gang_boss_slash.png") && entry.reason === "actionExists"));
  assert.equal(fs.readFileSync(tuningFile, "utf8"), tuningBefore);
  assert.equal(fs.readFileSync(manifestFile, "utf8"), manifestBefore);
});

test("idle visible-height baseline uses non-uniform Y scale and frame Y override", (t) => {
  const { sourceRoot, pipeline } = makePipeline(t);
  const state = pipeline.load();
  state.tuning.values["profiles.warden_shield.groups.idle.visual_scale"] = { x: 9, y: 0.2 };
  state.tuning.frame_visual_overrides["warden_shield/idle:0"] = { visual_scale: { x: 7, y: 0.75 } };
  pipeline.save(state);
  const idle = profileOf(pipeline, "warden_shield").animations.find((animation) => animation.id === "idle");
  const idleBounds = opaqueBoundsForPng(pipeline.asset(idle.frames[0].path));
  writePng(sourceRoot, "01a_warden_shield", "warden_shield_move.png", {
    width: 300,
    height: 600,
    rect: { x: 100, y: 120, width: 80, height: 400 },
  });
  const report = pipeline.scanAssets();
  const move = profileOf(pipeline, "warden_shield").animations.find((animation) => animation.id === "move");
  const moveBounds = opaqueBoundsForPng(path.join(sourceRoot, "01a_warden_shield", "warden_shield_move.png"));
  assert.ok(Math.abs(move.defaultScale - 0.75 * idleBounds.height / moveBounds.height) < 0.00001);
  assert.equal(report.addedActions[0].baseline.effectiveScale, 0.75);
});

test("existing hit effect is preserved and a discovered VFX stays a calibration hint", (t) => {
  const { sourceRoot, pipeline } = makePipeline(t);
  const before = pipeline.load().metadata.profiles.fish;
  const existingTexture = before.visual.hitEffectTexture;
  assert.ok(existingTexture);
  writePng(sourceRoot, "12a_fish", "fish_VFX.png", { width: 360, height: 180 });
  const report = pipeline.scanAssets();
  const after = pipeline.load().metadata.profiles.fish;
  assert.equal(after.visual.hitEffectTexture, existingTexture);
  assert.equal(after.discoveredVfx, undefined);
  assert.ok(report.skipped.some((entry) => entry.file.endsWith("fish_VFX.png") && entry.reason === "existingHitEffectTexture"));
  assert.equal(report.addedEffects.length, 0);
});

test("missing idle imports existing actions without fabricating idle and still blocks publish", (t) => {
  const { sourceRoot, pipeline } = makePipeline(t);
  writePng(sourceRoot, "09a_mirror_inspector", "mirror_inspector_attack.png", { width: 240, height: 400 });
  writePng(sourceRoot, "09a_mirror_inspector", "mirror_inspector_damaged.png", { width: 240, height: 400 });
  writePng(sourceRoot, "09a_mirror_inspector", "mirror_inspector_VFX.png", { width: 400, height: 200 });

  const report = pipeline.scanAssets();
  assert.deepEqual(report.addedProfiles.map((entry) => entry.id), ["mirror_inspector"]);
  assert.equal(report.addedProfiles[0].label, "镜面监察员");
  assert.deepEqual(report.addedActions.map((entry) => entry.action), ["pierce", "damaged"]);
  assert.deepEqual(report.addedEffects.map((entry) => entry.profileId), ["mirror_inspector"]);
  assert.deepEqual(report.missingIdle, ["mirror_inspector"]);
  assert.ok(report.missingIdle.every((entry) => typeof entry === "string"));

  const profile = profileOf(pipeline, "mirror_inspector");
  assert.equal(profile.label, "镜面监察员");
  assert.deepEqual(actionIds(profile), ["pierce", "damaged"]);
  assert.ok(!actionIds(profile).includes("idle"));
  const mirrorMeta = pipeline.load().metadata.profiles.mirror_inspector;
  assert.ok(fs.existsSync(pipeline.asset(mirrorMeta.visual.hitEffectTexture)));
  assert.equal(mirrorMeta.discoveredVfx.source.endsWith("mirror_inspector_VFX.png"), true);
  assert.throws(() => pipeline.compile(["mirror_inspector"]), /缺少idle/);
  assert.throws(() => pipeline.publish(["mirror_inspector"]), /缺少idle/);
  assert.ok(!fs.existsSync(pipeline.publishedFile));
});

test("directory and strict prefix filters exclude references and accept case-insensitive suffixes", (t) => {
  const { sourceRoot, pipeline } = makePipeline(t);
  writePng(sourceRoot, "99z_new_watch", "NEW_WATCH_IDLE.PNG", { width: 220, height: 360 });
  writePng(sourceRoot, "99z_new_watch", "NEW_WATCH_ATTACK.PNG", { width: 220, height: 360 });
  writePng(sourceRoot, "99z_new_watch", "new_watch_move.png", { width: 220, height: 360 });
  writePng(sourceRoot, "99z_new_watch", "new_watch_extra_idle.png", { width: 220, height: 360 });
  writePng(sourceRoot, "99z_new_watch", "other_role_idle.png", { width: 220, height: 360 });
  writePng(sourceRoot, "99z_new_watch", "nested/new_watch_damaged.png", { width: 220, height: 360 });
  writePng(sourceRoot, "reference_idle", "warden_shield_idle.png", { width: 220, height: 360 });
  writePng(sourceRoot, "01a_reference_idle", "reference_idle_idle.png", { width: 220, height: 360 });
  writePng(sourceRoot, "bad name", "bad_role_idle.png", { width: 220, height: 360 });
  fs.writeFileSync(path.join(sourceRoot, "99z_new_watch", "new_watch_notes.txt"), "ignored");

  const report = pipeline.scanAssets();
  assert.deepEqual(report.addedProfiles.map((entry) => entry.id), ["new_watch"]);
  const profile = profileOf(pipeline, "new_watch");
  assert.deepEqual(actionIds(profile), ["idle", "move", "pierce"]);
  assert.equal(profile.animations.find((animation) => animation.id === "pierce").name, "攻击");
  assert.deepEqual(report.missingIdle, []);
  assert.equal(profileOf(pipeline, "reference_idle"), undefined);
  assert.ok(report.skipped.some((entry) => entry.reason === "referenceDirectory"));
  assert.ok(report.skipped.some((entry) => entry.reason === "invalidDirectoryName"));
  assert.ok(report.skipped.some((entry) => entry.file.endsWith("other_role_idle.png") && entry.reason === "rolePrefixMismatch"));
  assert.ok(report.skipped.some((entry) => entry.file.endsWith("new_watch_extra_idle.png") && entry.reason === "unknownActionSuffix"));
  assert.ok(!report.skipped.some((entry) => entry.file.includes("nested")));
});

test("bad PNGs, duplicate actions and symlinks are reported per file without aborting the scan", (t) => {
  const { root, sourceRoot, pipeline } = makePipeline(t);
  writePng(sourceRoot, "01a_bad_role", "bad_role_idle.png", { width: 220, height: 360 });
  writePng(sourceRoot, "01a_bad_role", "bad_role_move.png", { bytes: Buffer.from("not a png") });
  writePng(sourceRoot, "01a_bad_role", "bad_role_attack.png", { width: 220, height: 360 });
  writePng(sourceRoot, "01a_bad_role", "bad_role_pierce.png", { width: 220, height: 360 });
  writePng(sourceRoot, "01a_bad_role", "bad_role_block.png", { width: 220, height: 360 });
  const truncated = pngBuffer({ width: 220, height: 360 });
  writePng(sourceRoot, "01a_bad_role", "bad_role_retreat.png", { bytes: truncated.subarray(0, Math.floor(truncated.length / 2)) });

  const outside = path.join(root, "outside", "escape");
  fs.mkdirSync(outside, { recursive: true });
  fs.writeFileSync(path.join(outside, "escape_idle.png"), pngBuffer({ width: 100, height: 120 }));
  let linkedDirectory = false;
  let linkedFile = false;
  try {
    fs.symlinkSync(outside, path.join(sourceRoot, "02b_escape"), "junction");
    linkedDirectory = true;
  } catch (error) {
    t.diagnostic(`目录符号链接不可用: ${error.code || error.message}`);
  }
  try {
    fs.symlinkSync(path.join(outside, "escape_idle.png"), path.join(sourceRoot, "01a_bad_role", "bad_role_shoot.png"), "file");
    linkedFile = true;
  } catch (error) {
    t.diagnostic(`文件符号链接不可用: ${error.code || error.message}`);
  }

  const report = pipeline.scanAssets();
  assert.equal(report.ok, true);
  const profile = profileOf(pipeline, "bad_role");
  assert.deepEqual(actionIds(profile), ["idle", "block"]);
  assert.ok(report.skipped.some((entry) => entry.file.endsWith("bad_role_move.png") && entry.reason === "invalidPng"));
  assert.ok(report.skipped.some((entry) => entry.file.endsWith("bad_role_retreat.png") && entry.reason === "invalidPng"));
  const duplicates = report.skipped.filter((entry) => entry.reason === "duplicateAction").map((entry) => entry.file);
  assert.ok(duplicates.some((file) => file.endsWith("bad_role_attack.png")));
  assert.ok(duplicates.some((file) => file.endsWith("bad_role_pierce.png")));
  assert.ok(report.warnings.some((entry) => entry.code === "duplicateAction"
    && /bad_role_attack\.png/.test(entry.message)
    && /bad_role_pierce\.png/.test(entry.message)));
  assert.ok(!actionIds(profile).includes("pierce"));
  if (linkedDirectory) assert.ok(report.skipped.some((entry) => entry.reason === "symlinkDirectory"));
  if (linkedFile) assert.ok(report.skipped.some((entry) => entry.reason === "symlinkFile"));
  assert.equal(pathInside(sourceRoot, outside), false);
  assert.equal(roleForDirectory("01a_warden_shield"), "warden_shield");
  assert.equal(roleForDirectory("reference_idle"), null);
});

test("repeated seed still scans and discovers new files added after the first seed", (t) => {
  const { sourceRoot, pipeline } = makePipeline(t, { seed: false });
  writePng(sourceRoot, "01a_seed_scan", "seed_scan_idle.png", { width: 220, height: 360 });
  pipeline.seed();
  assert.deepEqual(actionIds(profileOf(pipeline, "seed_scan")), ["idle"]);

  writePng(sourceRoot, "01a_seed_scan", "seed_scan_move.png", { width: 220, height: 360 });
  pipeline.seed();
  assert.deepEqual(actionIds(profileOf(pipeline, "seed_scan")), ["idle", "move"]);
  assert.ok(pipeline.status().autoImport.addedActions.some((entry) => entry.profileId === "seed_scan" && entry.action === "move"));
});

test("current character assets discover warden actions and mirror draft without writing formal worktrees", (t) => {
  const base = path.join(__dirname, "runtime");
  fs.mkdirSync(base, { recursive: true });
  const root = fs.mkdtempSync(path.join(base, "real-discovery-"));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const pipeline = createPipeline({
    workRoot: path.join(root, "authoring"),
    publishedFile: path.join(root, "published/catalog.json"),
    previewFile: path.join(root, "preview.json"),
    test: true,
  });
  pipeline.seed();
  const warden = profileOf(pipeline, "warden_shield");
  assert.ok(warden);
  for (const action of ["idle", "move", "pierce", "damaged"]) assert.ok(actionIds(warden).includes(action));
  assert.equal(warden.animations.find((animation) => animation.id === "pierce").name, "攻击");
  const mirror = profileOf(pipeline, "mirror_inspector");
  assert.ok(mirror);
  assert.equal(mirror.label, "镜面监察员");
	assert.ok(actionIds(mirror).includes("idle"));
  assert.ok(!actionIds(mirror).includes("move"));
  assert.ok(actionIds(mirror).includes("shoot"));
  assert.equal(pipeline.compile(["mirror_inspector"]).profiles.mirror_inspector.attackStyleOverride, "shoot");
  assert.ok(actionIds(mirror).includes("damaged"));
	assert.ok(!pipeline.status().autoImport.missingIdle.includes("mirror_inspector"));
});

test("luggage lurker's actual VFX PNG is discovered as an effect and not an actor pose",t=>{
  const {pipeline}=makePipeline(t,{sourceRoot:path.join(GAME,"assets/combat_test")});
  const state=pipeline.load(),meta=state.metadata.profiles.luggage_lurker;
  assert.ok(meta.visual.hitEffectTexture,"real luggage VFX must be registered by seed/scan");
  const expected=fs.readFileSync(path.join(GAME,"assets/combat_test/06b_luggage_lurker/luggage_lurker_VFX.png"));
  assert.deepEqual(fs.readFileSync(pipeline.asset(meta.visual.hitEffectTexture)),expected);
  assert.ok(!profileOf(pipeline,"luggage_lurker").animations.some(a=>/vfx/i.test(a.id)));
  assert.equal(meta.attacks.bite.impactTexture,"","a composite VFX is not automatically published as a single hit texture");
  assert.equal(pipeline.scanAssets().addedEffects.length,0,"rescanning retains the registered effect");
});
