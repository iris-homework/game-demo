"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const zlib = require("node:zlib");
const { createPipeline, GAME, read } = require("../pipeline.cjs");
const {
  ATTACK_FIELDS,
  ATTACK_TYPES,
  EFFECT_SLOTS,
  createAttackTemplate,
} = require("../attack_templates.cjs");

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
  return Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    chunk("IHDR", header),
    chunk("IDAT", zlib.deflateSync(raw)),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}

function fixture(t) {
  const base = path.join(__dirname, "runtime");
  fs.mkdirSync(base, { recursive: true });
  const root = fs.mkdtempSync(path.join(base, "attacks-"));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const sourceRoot = path.join(root, "source/combat_test");
  fs.mkdirSync(sourceRoot, { recursive: true });
  const pipeline = createPipeline({
    workRoot: path.join(root, "authoring"),
    publishedFile: path.join(root, "published/catalog.json"),
    previewFile: path.join(root, "preview.json"),
    sourceRoot,
    test: true,
  });
  pipeline.seed();
  return { root, sourceRoot, pipeline };
}

function writePng(sourceRoot, directory, fileName, options = {}) {
  const full = path.join(sourceRoot, directory, fileName);
  fs.mkdirSync(path.dirname(full), { recursive: true });
  fs.writeFileSync(full, pngBuffer(options));
  return full;
}

function resource(full) {
  return "res://" + path.relative(GAME, full).replaceAll("\\", "/");
}

function profileOf(pipeline, id) {
  return pipeline.load().manifest.profiles.find((profile) => profile.id === id);
}

test("default attack templates expose the complete contract and hit-compatible styles", () => {
  const hit = createAttackTemplate("hit");
  assert.deepEqual(Object.keys(hit).sort(), [...ATTACK_FIELDS].sort());
  assert.deepEqual(hit, {
    type: "hit",
    movement: "approach",
    windupPose: "move",
    strikePose: "hit",
    recoveryPose: "idle",
    windup: 0.1,
    impactDelay: 0.035,
    recovery: 0.12,
    flightTime: 0,
    muzzle: [0, 0],
    contact: [0, -62],
    muzzleTexture: "",
    projectileTexture: "",
    impactTexture: "",
  });
  assert.equal(createAttackTemplate("bite").strikePose, "bite_close");
  assert.equal(createAttackTemplate("bite").windup, 0.12);
  assert.equal(createAttackTemplate("shoot").movement, "stationary");
  assert.equal(createAttackTemplate("shoot").flightTime, 0.25);
  assert.equal(createAttackTemplate("laser").movement, "stationary");
  assert.equal(createAttackTemplate("slash").type, "hit");
  assert.equal(createAttackTemplate("pierce").type, "hit");
  const generatedHit = createAttackTemplate("hit", ["idle", "pierce"]);
  assert.equal(generatedHit.windupPose, "idle");
  assert.equal(generatedHit.strikePose, "pierce");
  assert.equal(createAttackTemplate("hit", ["idle", "move", "hit"]).windupPose, "move");
  assert.equal(createAttackTemplate("hit", ["idle", "move", "hit"]).strikePose, "hit");
  assert.equal(createAttackTemplate("bite", ["idle", "bite"]).strikePose, "bite_close");
  assert.deepEqual(ATTACK_TYPES, ["hit", "bite", "shoot", "laser"]);
  assert.deepEqual(EFFECT_SLOTS, ["muzzle", "projectile", "impact"]);
});

test("scan recognizes attack styles, classifies effects, and keeps legacy attack warnings", (t) => {
  const { sourceRoot, pipeline } = fixture(t);
  for (const [file, options] of [
    ["style_lab_idle.png", { width: 220, height: 360 }],
    ["style_lab_attack_hit.png", { width: 230, height: 360 }],
    ["style_lab_attack_bite.png", { width: 240, height: 360 }],
    ["style_lab_bite_close.png", { width: 245, height: 360 }],
    ["style_lab_attack_shoot.png", { width: 250, height: 360 }],
    ["style_lab_attack_laser.png", { width: 255, height: 360 }],
    ["style_lab_vfx_impact.png", { width: 100, height: 80 }],
  ]) writePng(sourceRoot, "55a_style_lab", file, options);
  writePng(sourceRoot, "55b_legacy_lab", "legacy_lab_idle.png", { width: 220, height: 360 });
  writePng(sourceRoot, "55b_legacy_lab", "legacy_lab_attack.png", { width: 230, height: 360 });

  const report = pipeline.scanAssets();
  assert.equal(report.ok, true);
  const profile = profileOf(pipeline, "style_lab");
  assert.deepEqual(profile.animations.map((entry) => entry.id).sort(), ["bite", "bite_close", "hit", "idle", "laser", "shoot"]);
  const meta = pipeline.load().metadata.profiles.style_lab;
  assert.deepEqual(Object.keys(meta.attacks).sort(), ["bite", "hit", "laser", "shoot"]);
  assert.equal(meta.attacks.hit.type, "hit");
  assert.equal(meta.attacks.bite.strikePose, "bite_close");
  assert.equal(meta.attacks.shoot.flightTime, 0.25);
  assert.equal(meta.visual.attackStyleOverride || "", "");
  assert.equal(profile.animations.find((entry) => entry.id === "hit").name, "打击");
  assert.ok(meta.attackEffects.impact.startsWith("res://"));
  assert.equal(meta.attacks.shoot.impactTexture, "", "multiple templates must not receive a shared effect arbitrarily");
  assert.ok(report.warnings.some((entry) => entry.code === "multipleAttackStylesNeedSelection"));
  assert.ok(report.warnings.some((entry) => entry.code === "attackEffectNeedsExplicitAssociation"));
  assert.throws(() => pipeline.compile(["style_lab"]), /选择默认攻击方式/);

  const legacy = pipeline.load().metadata.profiles.legacy_lab;
  assert.ok(profileOf(pipeline, "legacy_lab").animations.some((entry) => entry.id === "pierce"));
  assert.equal(legacy.visual.attackStyleOverride || "", "");
  assert.equal(legacy.attacks, undefined, "an untyped legacy attack keeps the old profile path");
  assert.ok(report.warnings.some((entry) => entry.code === "legacyAttackNoStyle" && /未标明攻击类型/.test(entry.message)));
});

test("attack_bite_close imports a closure into the same bite template and preserves manual tuning", (t) => {
  const { sourceRoot, pipeline } = fixture(t);
  writePng(sourceRoot, "64a_bite_lab", "bite_lab_idle.png");
  writePng(sourceRoot, "64a_bite_lab", "bite_lab_attack_bite.png");
  writePng(sourceRoot, "64a_bite_lab", "bite_lab_attack_bite_close.png");
  const report = pipeline.scanAssets();
  assert.equal(report.ok, true);
  assert.deepEqual(profileOf(pipeline, "bite_lab").animations.map(a => a.id).sort(), ["bite", "bite_close", "idle"]);
  let meta = pipeline.load().metadata.profiles.bite_lab;
  assert.deepEqual(Object.keys(meta.attacks), ["bite"]);
  assert.equal(meta.attacks.bite.strikePose, "bite_close");
  assert.equal(meta.visual.attackStyleOverride, "bite");
  assert.equal(pipeline.compile(["bite_lab"]).profiles.bite_lab.pipelineAttacks.bite.strikePose, "bite_close");
  pipeline.setMetadata({profileId:"bite_lab", attacks:{bite:{...meta.attacks.bite,windup:0.63}}});
  pipeline.scanAssets();
  meta = pipeline.load().metadata.profiles.bite_lab;
  assert.equal(meta.attacks.bite.windup, 0.63);
  assert.deepEqual(Object.keys(meta.attacks), ["bite"]);
  // Both spellings target one slot: ambiguity must be reported, never chosen arbitrarily.
  writePng(sourceRoot, "65a_bite_conflict", "bite_conflict_idle.png");
  writePng(sourceRoot, "65a_bite_conflict", "bite_conflict_attack_bite.png");
  writePng(sourceRoot, "65a_bite_conflict", "bite_conflict_bite_close.png");
  writePng(sourceRoot, "65a_bite_conflict", "bite_conflict_attack_bite_close.png");
  const conflict = pipeline.scanAssets();
  assert.ok(conflict.warnings.some(w => w.code === "duplicateAction" && w.message.includes("bite_conflict")));
  assert.ok(!profileOf(pipeline, "bite_conflict").animations.some(a => a.id === "bite_close"));
  assert.throws(() => pipeline.compile(["bite_conflict"]), /bite_close/);
});

test("renamed legacy attack repairs a missing reference without losing calibration", (t) => {
  const { sourceRoot, pipeline } = fixture(t);
  writePng(sourceRoot,"66a_rename_lab","rename_lab_idle.png");
  const previous=writePng(sourceRoot,"66a_rename_lab","rename_lab_attack.png");
  pipeline.scanAssets();
  const saved=pipeline.load();
  const legacy=saved.manifest.profiles.find(p=>p.id==="rename_lab").animations.find(a=>a.id==="pierce");
  legacy.frames[0].path=resource(previous);
  legacy.sourceAnchor={x:123,y:345};
  pipeline.save(saved);
  fs.renameSync(previous,path.join(path.dirname(previous),"rename_lab_attack_bite.png"));
  writePng(sourceRoot,"66a_rename_lab","rename_lab_attack_bite_close.png");
  const report=pipeline.scanAssets();
  const repaired=profileOf(pipeline,"rename_lab").animations.find(a=>a.id==="pierce");
  assert.deepEqual(repaired.sourceAnchor,{x:123,y:345});
  assert.ok(repaired.frames[0].path!==resource(previous));
  assert.ok(report.warnings.some(w=>w.code==="renamedLegacyAttack"));
  assert.equal(pipeline.compile(["rename_lab"]).profiles.rename_lab.pipelineAttacks.bite.strikePose,"bite_close");
});

test("scan attaches effect slots only to a unique empty attack template and preserves manual values", (t) => {
  const { sourceRoot, pipeline } = fixture(t);
  writePng(sourceRoot, "56a_shoot_lab", "shoot_lab_idle.png");
  writePng(sourceRoot, "56a_shoot_lab", "shoot_lab_attack_shoot.png");
  writePng(sourceRoot, "56a_shoot_lab", "shoot_lab_vfx_muzzle.png", { width: 100, height: 80 });
  writePng(sourceRoot, "56a_shoot_lab", "shoot_lab_vfx_projectile.png", { width: 80, height: 40 });
  writePng(sourceRoot, "56a_shoot_lab", "shoot_lab_vfx_impact.png", { width: 70, height: 70 });
  pipeline.scanAssets();
  let meta = pipeline.load().metadata.profiles.shoot_lab;
  assert.equal(meta.visual.attackStyleOverride, "shoot");
  for (const slot of EFFECT_SLOTS) {
    assert.ok(meta.attackEffects[slot].startsWith("res://"));
    assert.equal(meta.attacks.shoot[`${slot}Texture`], meta.attackEffects[slot]);
  }

  const manual = { ...meta.attacks.shoot, windup: 0.77, muzzle: [12, 34], impactTexture: meta.attackEffects.impact };
  pipeline.setMetadata({ profileId: "shoot_lab", attacks: { shoot: manual }, attackStyle: "pierce" });
  writePng(sourceRoot, "56a_shoot_lab", "shoot_lab_attack_laser.png");
  writePng(sourceRoot, "56a_shoot_lab", "shoot_lab_vfx_projectile.png", { width: 90, height: 50 });
  const report = pipeline.scanAssets();
  meta = pipeline.load().metadata.profiles.shoot_lab;
  assert.deepEqual(meta.attacks.shoot, manual);
  assert.ok(meta.attacks.laser);
  assert.equal(meta.visual.attackStyleOverride, "pierce");
  assert.ok(report.skipped.some((entry) => entry.reason === "existingAttackEffectTexture"));
});

test("same action slot conflict is reported without choosing either file", (t) => {
  const { sourceRoot, pipeline } = fixture(t);
  writePng(sourceRoot, "57a_conflict_lab", "conflict_lab_idle.png");
  writePng(sourceRoot, "57a_conflict_lab", "conflict_lab_attack_hit.png");
  writePng(sourceRoot, "57a_conflict_lab", "conflict_lab_hit.png");
  const report = pipeline.scanAssets();
  assert.equal(report.ok, true);
  const profile = profileOf(pipeline, "conflict_lab");
  assert.deepEqual(profile.animations.map((entry) => entry.id), ["idle"]);
  assert.ok(report.warnings.some((entry) => entry.code === "duplicateAction" && /conflict_lab_attack_hit\.png/.test(entry.message)));
  assert.ok(report.skipped.some((entry) => entry.file.endsWith("conflict_lab_hit.png") && entry.reason === "duplicateAction"));
});

test("legacy attack pierce and attack_hit occupy separate slots", (t) => {
  const { sourceRoot, pipeline } = fixture(t);
  writePng(sourceRoot, "57b_compat_lab", "compat_lab_idle.png");
  writePng(sourceRoot, "57b_compat_lab", "compat_lab_attack.png");
  writePng(sourceRoot, "57b_compat_lab", "compat_lab_attack_hit.png");
  const report = pipeline.scanAssets();
  const profile = profileOf(pipeline, "compat_lab");
  assert.deepEqual(profile.animations.map((entry) => entry.id), ["idle", "pierce", "hit"]);
  assert.ok(!report.warnings.some((entry) => entry.code === "duplicateAction"));
  const meta = pipeline.load().metadata.profiles.compat_lab;
  assert.equal(meta.attacks.hit.type, "hit");
  assert.equal(meta.attacks.pierce, undefined);
  assert.equal(meta.visual.attackStyleOverride, "hit");
  assert.equal(meta.attacks.hit.windupPose, "idle");
  assert.doesNotThrow(() => pipeline.compile(["compat_lab"]));
});

test("noren receives an attack template without a forced style override", (t) => {
  const { sourceRoot, pipeline } = fixture(t);
  writePng(sourceRoot, "noren", "noren_attack_laser.png");
  pipeline.scanAssets();
  const meta = pipeline.load().metadata.profiles.noren;
  assert.ok(meta.attacks.laser);
  assert.equal(meta.visual.attackStyleOverride, undefined);
});

test("an explicit empty attack style survives scans with multiple new templates", (t) => {
  const { sourceRoot, pipeline } = fixture(t);
  writePng(sourceRoot, "62a_manual_default", "manual_default_idle.png");
  pipeline.scanAssets();
  pipeline.setMetadata({ profileId: "manual_default", attackStyle: "" });
  writePng(sourceRoot, "62a_manual_default", "manual_default_attack_hit.png");
  writePng(sourceRoot, "62a_manual_default", "manual_default_attack_bite.png");
  writePng(sourceRoot, "62a_manual_default", "manual_default_bite_close.png");
  writePng(sourceRoot, "62a_manual_default", "manual_default_attack_shoot.png");
  const report = pipeline.scanAssets();
  const meta = pipeline.load().metadata.profiles.manual_default;
  assert.equal(meta.attackStyleManual, true);
  assert.equal(meta.visual.attackStyleOverride, "");
  assert.deepEqual(Object.keys(meta.attacks).sort(), ["bite", "hit", "shoot"]);
  assert.ok(!report.warnings.some((entry) => entry.code === "multipleAttackStylesNeedSelection"));
});

test("a later second template clears an automatic default and warns instead of picking one", (t) => {
  const { sourceRoot, pipeline } = fixture(t);
  writePng(sourceRoot, "63a_multi_default", "multi_default_idle.png");
  writePng(sourceRoot, "63a_multi_default", "multi_default_attack_hit.png");
  pipeline.scanAssets();
  let meta = pipeline.load().metadata.profiles.multi_default;
  assert.equal(meta.visual.attackStyleOverride, "hit");
  assert.equal(meta.attackStyleAuto, true);

  writePng(sourceRoot, "63a_multi_default", "multi_default_attack_bite.png");
  writePng(sourceRoot, "63a_multi_default", "multi_default_bite_close.png");
  const report = pipeline.scanAssets();
  meta = pipeline.load().metadata.profiles.multi_default;
  assert.equal(meta.visual.attackStyleOverride || "", "");
  assert.equal(meta.attackStyleAuto, undefined);
  assert.equal(meta.attackStyleManual, undefined);
  assert.ok(report.warnings.some((entry) => entry.code === "multipleAttackStylesNeedSelection"
    && entry.styles.includes("hit") && entry.styles.includes("bite")));
});

test("metadata validates complete attacks atomically and allows draft poses", (t) => {
  const { pipeline } = fixture(t);
  const before = pipeline.revision();
  assert.throws(() => pipeline.setMetadata({ profileId: "warden_shield", attacks: [] }), /attacks 必须是/);
  assert.throws(() => pipeline.setMetadata({ profileId: "warden_shield", attacks: { hit: { ...createAttackTemplate("hit"), movement: "run" } } }), /movement/);
  assert.throws(() => pipeline.setMetadata({ profileId: "warden_shield", attacks: { hit: { ...createAttackTemplate("hit"), windup: -1 } } }), /windup/);
  assert.throws(() => pipeline.setMetadata({ profileId: "warden_shield", attacks: { shoot: { ...createAttackTemplate("shoot"), movement: "approach" } } }), /stationary 或 retreat/);
  assert.throws(() => pipeline.setMetadata({ profileId: "warden_shield", attacks: { hit: { ...createAttackTemplate("hit"), flightTime: 10.01 } } }), /0～10/);
  assert.throws(() => pipeline.setMetadata({ profileId: "warden_shield", attacks: { hit: { ...createAttackTemplate("hit"), impactTexture: "https://example.test/hit.png" } } }), /res:\/\//);
  assert.throws(() => pipeline.setMetadata({ profileId: "warden_shield", attacks: { hit: { ...createAttackTemplate("hit"), muzzle: [0, 100001] } } }), /100000/);
  assert.equal(pipeline.revision(), before);

  pipeline.setMetadata({ profileId: "warden_shield", attacks: { hit: { ...createAttackTemplate("hit"), muzzle: [-12, 34], contact: [-100000, 100000], windup: 10 } } });
  assert.deepEqual(pipeline.load().metadata.profiles.warden_shield.attacks.hit.muzzle, [-12, 34]);

  const draft = { ...createAttackTemplate("hit"), windupPose: "idle", strikePose: "idle", recoveryPose: "" };
  pipeline.setMetadata({ profileId: "warden_shield", attacks: { hit: draft } });
  assert.equal(pipeline.load().metadata.profiles.warden_shield.attacks.hit.recoveryPose, "");
  assert.throws(() => pipeline.compile(["warden_shield"]), /攻击模板 hit\.recoveryPose 尚未选择姿势/);
});

test("bite never falls back when bite_close is absent and permits an explicit idle strike", (t) => {
  const { sourceRoot, pipeline } = fixture(t);
  writePng(sourceRoot, "58a_bite_lab", "bite_lab_idle.png");
  writePng(sourceRoot, "58a_bite_lab", "bite_lab_attack_bite.png");
  pipeline.scanAssets();
  assert.throws(() => pipeline.compile(["bite_lab"]), /咬击模板 bite 缺少 bite_close.*不会自动回退 idle/);
  const attack = pipeline.load().metadata.profiles.bite_lab.attacks.bite;
  pipeline.setMetadata({ profileId: "bite_lab", attacks: { bite: { ...attack, strikePose: "idle" } } });
  const compiled = pipeline.compile(["bite_lab"]).profiles.bite_lab;
  assert.equal(compiled.pipelineAttacks.bite.strikePose, "idle");
  assert.deepEqual(compiled.pipelineAttacks.bite.contact, [0, -62]);
});

test("laser templates bypass legacy pose/palm requirements while the old style path still validates", (t) => {
  const { sourceRoot, pipeline } = fixture(t);
  writePng(sourceRoot, "60a_laser_lab", "laser_lab_idle.png");
  pipeline.scanAssets();
  const attack = {
    ...createAttackTemplate("laser"),
    windupPose: "idle",
    strikePose: "idle",
  };
  pipeline.setMetadata({ profileId: "laser_lab", attackStyle: "laser", attacks: { laser: attack } });
  const compiled = pipeline.compile(["laser_lab"]).profiles.laser_lab;
  assert.equal(compiled.pipelineAttacks.laser.strikePose, "idle");
  assert.equal(compiled.laserPalmWidth, undefined);

  const old = pipeline.load();
  delete old.metadata.profiles.laser_lab.attacks;
  old.metadata.profiles.laser_lab.visual.attackStyleOverride = "laser";
  pipeline.save(old);
  assert.throws(() => pipeline.compile(["laser_lab"]), /攻击方式需要 laser/);
});

test("attack templates resolve pose aliases like the runtime parser", (t) => {
  const { sourceRoot, pipeline } = fixture(t);
  writePng(sourceRoot, "61a_alias_lab", "alias_lab_idle.png");
  pipeline.scanAssets();
  const state = pipeline.load();
  const profile = state.manifest.profiles.find((entry) => entry.id === "alias_lab");
  profile.animations.push({ ...profile.animations[0], id: "move", name: "move" });
  state.metadata.profiles.alias_lab.visual.poseAliases = { dash: "move" };
  pipeline.save(state);
  pipeline.setMetadata({
    profileId: "alias_lab",
    attacks: { hit: { ...createAttackTemplate("hit"), windupPose: "dash", strikePose: "idle" } },
  });
  assert.equal(pipeline.compile(["alias_lab"]).profiles.alias_lab.pipelineAttacks.hit.windupPose, "dash");
});

test("legacy profiles without attacks remain unchanged and retain their effect requirement", (t) => {
  const { pipeline } = fixture(t);
  const state = pipeline.load();
  assert.equal(pipeline.load().metadata.profiles.fish.attacks, undefined);
  const fish = pipeline.compile(["fish"]).profiles.fish;
  assert.equal(fish.pipelineAttacks, undefined);
  assert.equal(fish.attackStyleOverride, "bite");
  state.metadata.profiles.fish.visual.hitEffectTexture = "";
  pipeline.save(state);
  assert.throws(() => pipeline.compile(["fish"]), /旧咬击演出需要命中特效PNG/);
});

test("publish freezes attack textures and rollback restores only the catalog snapshot", (t) => {
  const { root, sourceRoot, pipeline } = fixture(t);
  writePng(sourceRoot, "59a_resource_lab", "resource_lab_idle.png");
  writePng(sourceRoot, "59a_resource_lab", "resource_lab_attack_shoot.png");
  writePng(sourceRoot, "59a_resource_lab", "resource_lab_vfx_muzzle.png", { width: 101, height: 81 });
  writePng(sourceRoot, "59a_resource_lab", "resource_lab_vfx_projectile.png", { width: 81, height: 41 });
  writePng(sourceRoot, "59a_resource_lab", "resource_lab_vfx_impact.png", { width: 71, height: 71 });
  pipeline.scanAssets();
  const compiled = pipeline.compile(["resource_lab"]).profiles.resource_lab;
  assert.ok(Object.values(compiled.pipelineAttacks.shoot).some((value) => typeof value === "string" && value.startsWith("res://")));

  const first = pipeline.publish(["resource_lab"]);
  const firstCatalog = read(pipeline.publishedFile);
  const firstAttack = firstCatalog.profiles.resource_lab.pipelineAttacks.shoot;
  assert.match(firstAttack.muzzleTexture, /\/published\/assets\//);
  assert.ok(fs.existsSync(pipeline.asset(firstAttack.muzzleTexture)));
  assert.equal(pipeline.asset(firstAttack.muzzleTexture).startsWith(path.join(root, "published")), true);

  const replacement = writePng(sourceRoot, "59a_resource_lab", "replacement_impact.png", { width: 73, height: 74 });
  const metadata = pipeline.load();
  const current = metadata.metadata.profiles.resource_lab.attacks.shoot;
  pipeline.setMetadata({
    profileId: "resource_lab",
    attacks: { shoot: { ...current, impactTexture: resource(replacement) } },
  });
  const second = pipeline.publish(["resource_lab"]);
  const secondCatalog = read(pipeline.publishedFile);
  assert.notEqual(secondCatalog.profiles.resource_lab.pipelineAttacks.shoot.impactTexture, firstAttack.impactTexture);
  assert.ok(fs.existsSync(pipeline.asset(secondCatalog.profiles.resource_lab.pipelineAttacks.shoot.impactTexture)));

  pipeline.rollback(second.backupId);
  assert.deepEqual(read(pipeline.publishedFile), firstCatalog);
  assert.ok(fs.existsSync(pipeline.asset(firstAttack.impactTexture)), "rollback keeps resources referenced by the restored catalog");
});
