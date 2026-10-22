"use strict";

const fs = require("node:fs");
const path = require("node:path");

const DIRECTORY_ROLE = /^\d{2}[a-z]_(.+)$/i;
const ROLE_ID = /^[a-z][a-z0-9_]{0,63}$/;
const REFERENCE_DIRECTORY = /^reference(?:$|[_-])/i;
const ATTACK_SUFFIXES = new Map([
  ["attack_hit", { action: "hit", attackStyle: "hit", actionName: "打击" }],
  ["attack_bite", { action: "bite", attackStyle: "bite", actionName: "咬击" }],
  ["attack_bite_close", { action: "bite_close", attackStyle: "bite", actionName: "咬合" }],
  ["bite_close", { action: "bite_close", attackStyle: "bite", actionName: "咬合" }],
  ["attack_shoot", { action: "shoot", attackStyle: "shoot", actionName: "射击" }],
  ["attack_laser", { action: "laser", attackStyle: "laser", actionName: "掌心射线" }],
]);
const STYLE_ACTIONS = new Map([
  ["hit", "hit"],
  ["bite", "bite"],
  ["bite_close", "bite"],
  ["shoot", "shoot"],
  ["laser", "laser"],
  ["slash", "slash"],
  ["pierce", "pierce"],
]);

function pathInside(root, target) {
  const relative = path.relative(root, target);
  return relative === "" || (relative !== ".." && !relative.startsWith(`..${path.sep}`) && !path.isAbsolute(relative));
}

function roleForDirectory(name) {
  if (typeof name !== "string" || !name || name.startsWith(".")) return null;
  if (REFERENCE_DIRECTORY.test(name)) return null;
  const match = DIRECTORY_ROLE.exec(name);
  const role = (match ? match[1] : name).toLowerCase();
  if (REFERENCE_DIRECTORY.test(role)) return null;
  return ROLE_ID.test(role) ? role : null;
}

function compareNames(left, right) {
  return left.name < right.name ? -1 : left.name > right.name ? 1 : 0;
}

function suffixDescriptor(stem, role, actions) {
  const prefix = `${role}_`;
  if (!stem.toLowerCase().startsWith(prefix)) return { reason: "rolePrefixMismatch" };
  const suffix = stem.slice(role.length + 1).toLowerCase();
  if (!suffix) return { reason: "rolePrefixMismatch" };
  if (suffix === "vfx") {
    return { kind: "effect", action: null, actionName: "VFX", mappedFrom: null, effectSlot: "vfx" };
  }
  if (/^vfx_(muzzle|projectile|impact)$/.test(suffix)) {
    const slot = suffix.slice(4);
    return { kind: "effect", action: null, actionName: slot, mappedFrom: null, effectSlot: slot };
  }
  if (suffix === "attack") {
    return {
      kind: "action",
      action: "pierce",
      actionName: "攻击",
      mappedFrom: "attack",
      attackStyle: "pierce",
      legacyAttack: true,
      styleConfirmed: false,
    };
  }
  if (ATTACK_SUFFIXES.has(suffix)) {
    const attack = ATTACK_SUFFIXES.get(suffix);
    return {
      kind: "action",
      ...attack,
      mappedFrom: suffix,
      legacyAttack: false,
      styleConfirmed: true,
    };
  }
  if (actions.has(suffix)) {
    const attackStyle = STYLE_ACTIONS.get(suffix) || null;
    return {
      kind: "action",
      action: suffix,
      actionName: suffix,
      mappedFrom: null,
      attackStyle,
      legacyAttack: false,
      styleConfirmed: !!attackStyle,
    };
  }
  return { reason: "unknownActionSuffix" };
}

function skipped(entry, reason, message, extra = {}) {
  return { file: entry, reason, message, ...extra };
}

function scanSource(sourceRoot, options = {}) {
  const actions = options.actions instanceof Set ? options.actions : new Set(options.actions || []);
  const result = {
    sourceRoot: path.resolve(sourceRoot),
    directories: [],
    files: [],
    skipped: [],
    warnings: [],
  };
  let root;
  try {
    root = fs.realpathSync(sourceRoot);
    if (!fs.statSync(root).isDirectory()) throw new Error("扫描根不是目录");
  } catch (error) {
    result.warnings.push({ code: "sourceRootUnavailable", message: error.message, sourceRoot: sourceRoot });
    return result;
  }
  result.sourceRoot = root;

  let entries;
  try {
    entries = fs.readdirSync(root, { withFileTypes: true }).sort(compareNames);
  } catch (error) {
    result.warnings.push({ code: "sourceRootUnreadable", message: error.message, sourceRoot: root });
    return result;
  }

  const seen = new Map();
  for (const entry of entries) {
    const directoryRelative = entry.name;
    const directoryPath = path.join(root, entry.name);
    let directoryStat;
    try {
      directoryStat = fs.lstatSync(directoryPath);
    } catch (error) {
      result.skipped.push(skipped(directoryRelative, "unreadableDirectory", error.message));
      continue;
    }
    if (directoryStat.isSymbolicLink()) {
      result.skipped.push(skipped(directoryRelative, "symlinkDirectory", "符号链接目录不参与自动发现"));
      continue;
    }
    if (!directoryStat.isDirectory()) continue;
    let realDirectory;
    try {
      realDirectory = fs.realpathSync(directoryPath);
    } catch (error) {
      result.skipped.push(skipped(directoryRelative, "unreadableDirectory", error.message));
      continue;
    }
    if (!pathInside(root, realDirectory)) {
      result.skipped.push(skipped(directoryRelative, "outsideSourceRoot", "目录真实路径超出扫描根"));
      continue;
    }
    if (REFERENCE_DIRECTORY.test(entry.name)) {
      result.skipped.push(skipped(directoryRelative, "referenceDirectory", "参考目录不作为角色导入"));
      continue;
    }
    const role = roleForDirectory(entry.name);
    if (!role) {
      result.skipped.push(skipped(directoryRelative, "invalidDirectoryName", "目录名无法得到有效角色 ID"));
      continue;
    }
    result.directories.push({ directory: entry.name, role });

    let children;
    try {
      children = fs.readdirSync(realDirectory, { withFileTypes: true }).sort(compareNames);
    } catch (error) {
      result.skipped.push(skipped(directoryRelative, "unreadableDirectory", error.message));
      continue;
    }
    for (const child of children) {
      if (path.extname(child.name).toLowerCase() !== ".png") continue;
      const relative = path.posix.join(entry.name, child.name);
      const fullPath = path.join(realDirectory, child.name);
      let stat;
      try {
        stat = fs.lstatSync(fullPath);
      } catch (error) {
        result.skipped.push(skipped(relative, "unreadableFile", error.message));
        continue;
      }
      if (stat.isSymbolicLink()) {
        result.skipped.push(skipped(relative, "symlinkFile", "符号链接文件不参与自动发现"));
        continue;
      }
      if (!stat.isFile()) continue;
      let realFile;
      try {
        realFile = fs.realpathSync(fullPath);
      } catch (error) {
        result.skipped.push(skipped(relative, "unreadableFile", error.message));
        continue;
      }
      if (!pathInside(root, realFile)) {
        result.skipped.push(skipped(relative, "outsideSourceRoot", "文件真实路径超出扫描根"));
        continue;
      }
      const stem = path.basename(child.name, path.extname(child.name));
      const parsed = suffixDescriptor(stem, role, actions);
      if (parsed.reason) {
        result.skipped.push(skipped(relative, parsed.reason, "文件名不符合角色前缀与动作后缀约定"));
        continue;
      }
      const descriptor = {
        directory: entry.name,
        directoryPath: realDirectory,
        role,
        fileName: child.name,
        relative,
        fullPath: realFile,
        size: stat.size,
        kind: parsed.kind,
        action: parsed.action,
        actionName: parsed.actionName,
        mappedFrom: parsed.mappedFrom,
        attackStyle: parsed.attackStyle || null,
        legacyAttack: parsed.legacyAttack === true,
        styleConfirmed: parsed.styleConfirmed === true,
        effectSlot: parsed.effectSlot || null,
      };
      const slot = parsed.kind === "effect" ? parsed.effectSlot : parsed.action;
      const key = `${role}:${parsed.kind === "effect" ? "effect:" : "action:"}${slot}`;
      const previous = seen.get(key);
      if (previous) {
        previous.conflict = true;
        descriptor.conflict = true;
        const duplicateReason = parsed.kind === "effect" ? "duplicateEffect" : "duplicateAction";
        result.warnings.push({
          code: duplicateReason,
          profileId: role,
          action: slot,
          ...(parsed.kind === "effect" ? { effectSlot: slot } : {}),
          files: [previous.relative, relative],
          message: parsed.kind === "effect"
            ? `角色 ${role} 的特效槽 ${slot} 存在多个候选文件，请保留所需文件后重扫：${previous.relative}、${relative}`
            : `角色 ${role} 的动作 ${slot} 存在多个候选文件，已全部跳过：${previous.relative}、${relative}`,
        });
        result.skipped.push(skipped(relative, duplicateReason, parsed.kind === "effect" ? "同一角色特效槽存在多个候选文件" : "同一角色动作存在多个候选文件", {
          duplicateOf: previous.relative,
        }));
        if (!previous.duplicateReported) {
          previous.duplicateReported = true;
          result.skipped.push(skipped(previous.relative, duplicateReason, parsed.kind === "effect" ? "同一角色特效槽存在多个候选文件" : "同一角色动作存在多个候选文件", {
            duplicateOf: relative,
          }));
        }
      } else {
        seen.set(key, descriptor);
      }
      result.files.push(descriptor);
    }
  }
  result.files = result.files.filter((file) => !file.conflict);
  result.skipped.sort((left, right) => left.file < right.file ? -1 : left.file > right.file ? 1 : 0);
  return result;
}

module.exports = { pathInside, roleForDirectory, scanSource, suffixDescriptor };
