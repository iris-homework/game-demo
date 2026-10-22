"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const root = path.resolve(__dirname, "../..");

test("production enemy and published catalogs reference existing files with exact case", () => {
  const directories = new Map();
  let references = 0;
  function visit(value) {
    if (value && typeof value === "object") return Object.values(value).forEach(visit);
    if (typeof value !== "string" || !value.startsWith("res://")) return;
    references++;
    let parent = root;
    for (const segment of value.slice(6).split("/")) {
      assert.ok(segment && segment !== "." && segment !== "..", value);
      if (!directories.has(parent)) directories.set(parent, fs.readdirSync(parent));
      assert.ok(directories.get(parent).includes(segment), "Missing or incorrectly cased resource: " + value);
      parent = path.join(parent, segment);
    }
    assert.ok(fs.statSync(parent).isFile(), "Resource must be a file: " + value);
  }
  for (const file of ["data/enemies/combat_visuals.json", "enemy_asset_pipeline/published/catalog.json"]) {
    visit(JSON.parse(fs.readFileSync(path.join(root, file), "utf8")));
  }
  assert.ok(references > 0, "Catalog resource check must not be empty");
});
