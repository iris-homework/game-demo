"use strict";
// Each action owns its template. In particular, noren can keep melee and shooting.
class MidnightAttackEditor {
  constructor(root, changed) {
    this.root = root;
    this.changed = changed;
    this.attacks = {};
    this.animations = [];
    this.key = "hit";
    this.field = name => root.querySelector(`[data-attack="${name}"]`);
    root.querySelector("#attack-template").onchange = event => {
      this.capture();
      this.key = event.target.value;
      this.render();
    };
    root.querySelector("#enable-template").onclick = () => {
      this.attacks[this.key] = this.defaults(this.key);
      this.render();
      this.changed();
    };
    root.querySelector("#remove-template").onclick = () => {
      delete this.attacks[this.key];
      this.render();
      this.changed();
    };
    root.addEventListener("input", event => {
      if (!event.target.dataset.attack) return;
      this.capture();
      this.status();
      this.changed();
    });
    root.addEventListener("change", event => {
      if (!event.target.dataset.attack) return;
      if (event.target.dataset.attack === "type") {
        const ranged = ["shoot", "laser"].includes(event.target.value);
        if (ranged && this.field("movement").value === "approach") this.field("movement").value = "stationary";
      }
      this.capture();
      this.status();
    });
  }
  load(profile, animations) {
    this.attacks = structuredClone(profile.attacks || {});
    this.animations = animations;
    this.key = Object.keys(this.attacks)[0] || profile.visual.attackStyleOverride || "hit";
    if (!["hit", "slash", "pierce", "bite", "shoot", "laser"].includes(this.key)) this.key = "hit";
    this.render();
  }
  defaults(key) {
    const type = ["slash", "pierce"].includes(key) ? "hit" : key;
    const has = id => this.animations.some(animation => animation.id === id);
    const strike = key === "bite" ? "bite_close" : (has(key) ? key : key === "hit" && has("pierce") ? "pierce" : key);
    return { type, movement: ["shoot", "laser"].includes(type) ? "stationary" : "approach",
      windupPose: key === "bite" ? "bite" : (type === "hit" && has("move") ? "move" : "idle"),
      strikePose: strike, recoveryPose: "idle", windup: key === "bite" ? 0.12 : 0.1,
      impactDelay: type === "hit" ? 0.035 : 0, recovery: 0.12,
      flightTime: type === "shoot" ? 0.25 : type === "laser" ? 0.3 : 0,
      muzzle: [0, 0], contact: [0, -62], muzzleTexture: "", projectileTexture: "", impactTexture: "" };
  }
  select(key, enable = false) {
    this.capture();
    this.key = key;
    if (enable && !this.attacks[key]) this.attacks[key] = this.defaults(key);
    this.render();
  }
  capture() {
    const entry = this.attacks[this.key];
    if (!entry) return;
    for (const field of ["type", "movement", "windupPose", "strikePose", "recoveryPose", "muzzleTexture", "projectileTexture", "impactTexture"]) entry[field] = this.field(field).value.trim();
    for (const field of ["windup", "impactDelay", "recovery", "flightTime"]) entry[field] = Number(this.field(field).value);
    for (const field of ["muzzle", "contact"]) entry[field] = [Number(this.field(field + "X").value), Number(this.field(field + "Y").value)];
  }
  values() { this.capture(); return structuredClone(this.attacks); }
  setMuzzle(x, y) {
    if (!this.attacks[this.key]) return false;
    this.field("muzzleX").value = x;
    this.field("muzzleY").value = y;
    this.capture();
    this.changed();
    return true;
  }
  render() {
    this.root.querySelector("#attack-template").value = this.key;
    const entry = this.attacks[this.key];
    this.root.querySelector("#attack-fields").hidden = !entry;
    this.root.querySelector("#enable-template").hidden = !!entry;
    this.root.querySelector("#remove-template").hidden = !entry;
    if (entry) {
      for (const field of ["windupPose", "strikePose", "recoveryPose"]) {
        const options = this.animations.map(animation => new Option(animation.id, animation.id));
        if (!this.animations.some(animation => animation.id === entry[field])) options.unshift(new Option("缺少：" + entry[field], entry[field]));
        this.field(field).replaceChildren(...options);
      }
      for (const field of ["type", "movement", "windupPose", "strikePose", "recoveryPose", "windup", "impactDelay", "recovery", "flightTime", "muzzleTexture", "projectileTexture", "impactTexture"]) this.field(field).value = entry[field] ?? "";
      for (const field of ["muzzle", "contact"]) {
        this.field(field + "X").value = entry[field]?.[0] ?? 0;
        this.field(field + "Y").value = entry[field]?.[1] ?? 0;
      }
    }
    this.status();
  }
  status() {
    const entry = this.attacks[this.key];
    const status = this.root.querySelector("#attack-template-status");
    if (!entry) {
      status.textContent = "未启用动作模板，沿用已有游戏演出。可启用后绑定现有PNG；切换编辑动作不会改变角色的默认攻击。";
      status.dataset.valid = "true";
      return;
    }
    const missing = ["windupPose", "strikePose", "recoveryPose"].filter(field => !this.animations.some(animation => animation.id === entry[field]));
    const issues = missing.map(field => `缺少姿势 ${entry[field]}${field === "strikePose" && entry.type === "bite" ? "（闭合命中）" : ""}`);
    if (["shoot", "laser"].includes(entry.type) && entry.movement === "approach") issues.push("远程攻击请选择原地或后撤");
    for (const field of ["windup", "impactDelay", "recovery", "flightTime"]) if (!Number.isFinite(entry[field]) || entry[field] < 0 || entry[field] > 10) issues.push(`${field}需在0—10秒之间`);
    status.textContent = issues.length ? issues.join("；") + "。可保存草稿，补齐后才能预览与应用。" : `${entry.windupPose} → ${entry.strikePose}〔命中${["shoot", "laser"].includes(entry.type) ? "在传播结束后" : ""}〕 → ${entry.recoveryPose}。姿势绑定完整。`;
    status.dataset.valid = String(!issues.length);
  }
}
window.MidnightAttackEditor = MidnightAttackEditor;
