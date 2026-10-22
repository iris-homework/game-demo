"use strict";

const ATTACK_TYPES = Object.freeze(["hit", "bite", "shoot", "laser"]);
const ATTACK_MOVEMENTS = Object.freeze(["approach", "stationary", "retreat"]);
const ATTACK_STYLES = Object.freeze(["hit", "bite", "shoot", "laser", "slash", "pierce"]);
const EFFECT_SLOTS = Object.freeze(["muzzle", "projectile", "impact"]);
const ATTACK_FIELDS = Object.freeze([
  "type",
  "movement",
  "windupPose",
  "strikePose",
  "recoveryPose",
  "windup",
  "impactDelay",
  "recovery",
  "flightTime",
  "muzzle",
  "contact",
  "muzzleTexture",
  "projectileTexture",
  "impactTexture",
]);

const STYLE_TYPES = Object.freeze({
  hit: "hit",
  bite: "bite",
  shoot: "shoot",
  laser: "laser",
  slash: "hit",
  pierce: "hit",
});

const DEFAULT_ATTACKS = Object.freeze({
  hit: Object.freeze({
    type: "hit",
    movement: "approach",
    windupPose: "move",
    strikePose: "hit",
    recoveryPose: "idle",
    windup: 0.1,
    impactDelay: 0.035,
    recovery: 0.12,
    flightTime: 0,
    muzzle: Object.freeze([0, 0]),
    contact: Object.freeze([0, -62]),
    muzzleTexture: "",
    projectileTexture: "",
    impactTexture: "",
  }),
  bite: Object.freeze({
    type: "bite",
    movement: "approach",
    windupPose: "bite",
    strikePose: "bite_close",
    recoveryPose: "idle",
    windup: 0.12,
    impactDelay: 0.035,
    recovery: 0.12,
    flightTime: 0,
    muzzle: Object.freeze([0, 0]),
    contact: Object.freeze([0, -62]),
    muzzleTexture: "",
    projectileTexture: "",
    impactTexture: "",
  }),
  shoot: Object.freeze({
    type: "shoot",
    movement: "stationary",
    windupPose: "idle",
    strikePose: "shoot",
    recoveryPose: "idle",
    windup: 0.1,
    impactDelay: 0,
    recovery: 0.12,
    flightTime: 0.25,
    muzzle: Object.freeze([0, 0]),
    contact: Object.freeze([0, -62]),
    muzzleTexture: "",
    projectileTexture: "",
    impactTexture: "",
  }),
  laser: Object.freeze({
    type: "laser",
    movement: "stationary",
    windupPose: "idle",
    strikePose: "laser",
    recoveryPose: "idle",
    windup: 0.1,
    impactDelay: 0,
    recovery: 0.12,
    flightTime: 0,
    muzzle: Object.freeze([0, 0]),
    contact: Object.freeze([0, -62]),
    muzzleTexture: "",
    projectileTexture: "",
    impactTexture: "",
  }),
  slash: Object.freeze({
    type: "hit",
    movement: "approach",
    windupPose: "slash",
    strikePose: "slash",
    recoveryPose: "idle",
    windup: 0.1,
    impactDelay: 0.035,
    recovery: 0.12,
    flightTime: 0,
    muzzle: Object.freeze([0, 0]),
    contact: Object.freeze([0, -62]),
    muzzleTexture: "",
    projectileTexture: "",
    impactTexture: "",
  }),
  pierce: Object.freeze({
    type: "hit",
    movement: "approach",
    windupPose: "pierce",
    strikePose: "pierce",
    recoveryPose: "idle",
    windup: 0.1,
    impactDelay: 0.035,
    recovery: 0.12,
    flightTime: 0,
    muzzle: Object.freeze([0, 0]),
    contact: Object.freeze([0, -62]),
    muzzleTexture: "",
    projectileTexture: "",
    impactTexture: "",
  }),
});

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function poseNames(poses) {
  if (!poses) return null;
  if (poses instanceof Set || poses instanceof Map) return new Set(poses.keys());
  return new Set(Array.isArray(poses) ? poses : Object.keys(poses));
}

function createAttackTemplate(style, poses) {
  if (!Object.hasOwn(DEFAULT_ATTACKS, style)) throw Error(`未知攻击模板 ${style}`);
  const entry = clone(DEFAULT_ATTACKS[style]);
  const available = poseNames(poses);
  if (!available) return entry;
  const has = pose => available.has(pose);
  if (style === "bite") {
    entry.windupPose = "bite";
    entry.strikePose = "bite_close";
  } else if (["shoot", "laser"].includes(entry.type)) {
    entry.windupPose = "idle";
    entry.strikePose = style;
  } else {
    entry.windupPose = has("move") ? "move" : "idle";
    if (has(style)) entry.strikePose = style;
    else if (has("hit")) entry.strikePose = "hit";
    else if (has("pierce")) entry.strikePose = "pierce";
    else entry.strikePose = style;
  }
  entry.recoveryPose = "idle";
  return entry;
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function validateTexturePath(value, label) {
  if (typeof value !== "string") throw Error(`${label} 必须是 res:// PNG 路径或空字符串`);
  if (value === "") return "";
  if (value.includes("\\") || /[\u0000-\u001f]/.test(value)) throw Error(`${label} 路径包含无效字符`);
  if (!value.startsWith("res://")) throw Error(`${label} 必须使用 res:// 路径`);
  if (value.includes("?") || value.includes("#")) throw Error(`${label} 不能包含查询或片段`);
  const relative = value.slice(6);
  if (!relative || path_is_absolute(relative)) throw Error(`${label} 路径必须是游戏内相对路径`);
  if (relative.split("/").some((part) => part === ".." || part === ".")) throw Error(`${label} 路径不能包含 . 或 ..`);
  if (!relative.toLowerCase().endsWith(".png")) throw Error(`${label} 必须是 PNG 资源`);
  return value;
}

// Keep this module independent of Node's path implementation for browser-side tests.
function path_is_absolute(value) {
  return value.startsWith("/") || /^[A-Za-z]:[\\/]/.test(value);
}

function validatePose(value, label) {
  if (typeof value !== "string") throw Error(`${label} 必须是姿势名或空字符串`);
  const pose = value.trim();
  if (pose !== value) throw Error(`${label} 不能包含首尾空白`);
  if (/[\u0000-\u001f]/.test(pose)) throw Error(`${label} 包含无效字符`);
  if (pose.length > 64) throw Error(`${label} 不能超过 64 个字符`);
  return pose;
}

function validateFiniteNonNegative(value, label) {
  if (typeof value !== "number" || !Number.isFinite(value) || value < 0 || value > 10) {
    throw Error(`${label} 必须是 0～10 的数值`);
  }
  return value;
}

function validatePoint(value, label, minimum) {
  if (!Array.isArray(value) || value.length !== 2) throw Error(`${label} 需要两个数值坐标`);
  return value.map((item) => {
    if (typeof item !== "number" || !Number.isFinite(item) || (minimum !== null && item < minimum) || Math.abs(item) > 100000) {
      throw Error(`${label} 坐标的绝对值不能超过 100000`);
    }
    return item;
  });
}

function normalizeAttack(style, raw, label = `attacks.${style}`) {
  if (!isPlainObject(raw)) throw Error(`${label} 必须是对象`);
  for (const key of Object.keys(raw)) {
    if (!ATTACK_FIELDS.includes(key)) throw Error(`${label}.${key} 不是攻击模板合同字段`);
  }
  const entry = { ...createAttackTemplate(style), ...raw };
  if (!ATTACK_TYPES.includes(entry.type)) throw Error(`${label}.type 必须是 hit、bite、shoot 或 laser`);
  if (!ATTACK_MOVEMENTS.includes(entry.movement)) throw Error(`${label}.movement 必须是 approach、stationary 或 retreat`);
  if (["shoot", "laser"].includes(entry.type) && entry.movement === "approach") {
    throw Error(`${label}.movement 对 ${entry.type} 必须选择 stationary 或 retreat`);
  }
  entry.windupPose = validatePose(entry.windupPose, `${label}.windupPose`);
  entry.strikePose = validatePose(entry.strikePose, `${label}.strikePose`);
  entry.recoveryPose = validatePose(entry.recoveryPose, `${label}.recoveryPose`);
  entry.windup = validateFiniteNonNegative(entry.windup, `${label}.windup`);
  entry.impactDelay = validateFiniteNonNegative(entry.impactDelay, `${label}.impactDelay`);
  entry.recovery = validateFiniteNonNegative(entry.recovery, `${label}.recovery`);
  entry.flightTime = validateFiniteNonNegative(entry.flightTime, `${label}.flightTime`);
  entry.muzzle = validatePoint(entry.muzzle, `${label}.muzzle`, null);
  entry.contact = validatePoint(entry.contact, `${label}.contact`, null);
  entry.muzzleTexture = validateTexturePath(entry.muzzleTexture, `${label}.muzzleTexture`);
  entry.projectileTexture = validateTexturePath(entry.projectileTexture, `${label}.projectileTexture`);
  entry.impactTexture = validateTexturePath(entry.impactTexture, `${label}.impactTexture`);
  return entry;
}

function normalizeAttacks(raw) {
  if (!isPlainObject(raw)) throw Error("attacks 必须是动作风格到攻击模板的对象");
  const result = {};
  for (const [style, entry] of Object.entries(raw)) {
    if (!ATTACK_STYLES.includes(style)) throw Error(`未知攻击风格 ${style}`);
    result[style] = normalizeAttack(style, entry);
  }
  return result;
}

function validateAttackPoses(attacks, poses, aliases = {}) {
  for (const [style, entry] of Object.entries(attacks)) {
    for (const field of ["windupPose", "strikePose", "recoveryPose"]) {
      const pose = entry[field];
      if (!pose) throw Error(`攻击模板 ${style}.${field} 尚未选择姿势`);
      const resolved = Object.hasOwn(aliases || {}, pose) ? aliases[pose] : pose;
      if (!Object.hasOwn(poses || {}, resolved)) {
        if (entry.type === "bite" && field === "strikePose" && pose === "bite_close") {
          throw Error(`咬击模板 ${style} 缺少 bite_close；不会自动回退 idle。请补 bite_close 图片，或人工将 strikePose 设为 idle。`);
        }
        throw Error(`攻击模板 ${style}.${field} 引用的姿势 ${pose} 不存在`);
      }
    }
  }
}

module.exports = {
  ATTACK_TYPES,
  ATTACK_MOVEMENTS,
  ATTACK_STYLES,
  EFFECT_SLOTS,
  ATTACK_FIELDS,
  STYLE_TYPES,
  DEFAULT_ATTACKS,
  createAttackTemplate,
  defaultAttack: createAttackTemplate,
  normalizeAttack,
  normalizeAttacks,
  validateAttackPoses,
  validateTexturePath,
};
