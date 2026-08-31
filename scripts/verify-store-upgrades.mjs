#!/usr/bin/env node
// Synthetic, disk-backed SwiftData upgrade checks for the two integration parents.
// Run from the repository root on a Mac with Xcode: node scripts/verify-store-upgrades.mjs
// Generated sources, executables, and stores stay in a new temporary directory.
// This checks storage compatibility on macOS, not physical-iPhone acceptance.
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const parents = process.argv.slice(2);
if (!parents.length) parents.push("4824786", "01b70dd");
const appRoot = "ios/WhoopsApp/WhoopsApp/";
const directory = mkdtempSync(join(tmpdir(), "whoops-store-upgrades-"));
console.log(`Synthetic upgrade artifacts: ${directory}`);

function git(...args) {
  return execFileSync("git", args, { encoding: "utf8" });
}

function source(ref, path) {
  return ref ? git("show", `${ref}:${path}`) : readFileSync(path, "utf8");
}

function schema(ref) {
  const app = source(ref, `${appRoot}App/WhoopsApp.swift`);
  const container = app.match(/ModelContainer\(([\s\S]*?)\n        \)/);
  assert(container, "App ModelContainer declaration changed; update this check explicitly");
  const names = [...container[1].matchAll(/(\w+)\.self/g)].map((match) => match[1]);
  assert(names.length > 0);
  const paths = git("ls-tree", "-r", "--name-only", ref || "HEAD", "--", appRoot)
    .trim().split("\n").filter((path) => path.endsWith(".swift"));
  // Include incoming tracked files during an uncommitted merge.
  if (!ref) paths.push(...git("ls-files", "--", appRoot).trim().split("\n")
    .filter((path) => path.endsWith(".swift")));
  const models = new Map();
  for (const path of new Set(paths)) {
    for (const match of source(ref, path).matchAll(
      /@Model\s+final class (\w+) \{([\s\S]*?)\n    init\(/g,
    )) {
      const properties = match[2].split("\n")
        .filter((line) => line.trim() && !line.trim().startsWith("//"))
        .map((line) => {
          const field = line.match(/^\s*(?:@Attribute\(\.unique\) )?var (\w+): (String|Int|Double|Bool|Date|Data)(\?)?$/);
          assert(field, `Unsupported schema declaration in ${match[1]}: ${line}`);
          return { declaration: line, name: field[1], type: field[2], optional: !!field[3] };
        });
      assert(!models.has(match[1]), `Duplicate model ${match[1]}`);
      models.set(match[1], properties);
    }
  }
  return new Map(names.map((name) => {
    assert(models.has(name), `No model declaration for ${name}`);
    return [name, models.get(name)];
  }));
}

function value(model, field, seed = "seed") {
  const base = {
    String: `"synthetic-${model}-${field.name}-\\(${seed})"`,
    Int: `360 + ${seed}`,
    Double: `360.6 + Double(${seed})`,
    Bool: `(${seed} == 1)`,
    Date: `Date(timeIntervalSince1970: 1_700_000_000 + Double(${seed}))`,
    Data: `Data("synthetic-${model}-${field.name}-\\(${seed})".utf8)`,
  }[field.type];
  return field.optional ? `(${seed} == 0 ? nil : ${base})` : base;
}

function program(models, oldModels) {
  const definitions = [...models].map(([name, fields]) => `
@Model final class ${name} {
${fields.map((field) => field.declaration).join("\n")}
    init(seed: Int) {
${fields.map((field) => `        ${field.name} = ${value(name, field)}`).join("\n")}
    }
}`).join("\n");
  const operations = [...models].map(([name, fields]) => {
    if (!oldModels) return `for seed in 0...1 { context.insert(${name}(seed: seed)) }`;
    const oldFields = oldModels.get(name);
    if (!oldFields) return `
let newRows${name} = try context.fetch(FetchDescriptor<${name}>())
precondition(newRows${name}.isEmpty)
context.insert(${name}(seed: 0))`;
    for (const old of oldFields) assert(fields.some((field) => field.name === old.name
      && field.type === old.type && field.optional === old.optional), `${name}.${old.name} removed/changed`);
    return `
let rows${name} = try context.fetch(FetchDescriptor<${name}>()).sorted { $0.id < $1.id }
precondition(rows${name}.count == 2, "${name}: record count changed")
for (seed, row) in rows${name}.enumerated() {
${fields.map((field) => {
      const previous = oldFields.some((old) => old.name === field.name);
      assert(previous || field.optional, `${name}.${field.name}: new field is not optional`);
      return `    precondition(row.${field.name} == ${previous ? value(name, field) : "nil"}, "${name}.${field.name}: value changed")`;
    }).join("\n")}
}`;
  }).join("\n");
  return `import Foundation
import SwiftData
${definitions}

@main struct StoreCheck {
    @MainActor static func main() throws {
        let schema = Schema([${[...models.keys()].map((name) => `${name}.self`).join(", ")}])
        let configuration = ModelConfiguration(schema: schema, url: URL(fileURLWithPath: CommandLine.arguments[1]))
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        context.autosaveEnabled = false
        ${operations}
        try context.save()
        print("${oldModels ? "Verified" : "Seeded"} ${models.size} model types")
    }
}
`;
}

const current = schema(null);
for (const [index, parent] of parents.entries()) {
  const previous = schema(parent);
  for (const name of previous.keys()) assert(current.has(name), `Model ${name} removed`);
  const store = join(directory, `parent-${index}.store`);
  console.log(`Checking ${parent} (${previous.size} types) -> working tree (${current.size} types)`);
  for (const [stage, code] of [
    ["seed", program(previous, null)], ["verify", program(current, previous)],
  ]) {
    const file = join(directory, `${index}-${stage}.swift`);
    const binary = join(directory, `${index}-${stage}`);
    writeFileSync(file, code);
    // Keep the module identity stable across both executables, as in app upgrades.
    execFileSync("xcrun", ["swiftc", "-parse-as-library", "-module-name", "WhoopsApp",
      "-target", "arm64-apple-macos14.0", file, "-o", binary], { stdio: "inherit" });
    execFileSync(binary, [store], { stdio: "inherit" });
  }
  console.log(`PASS: all persisted fields from ${parent}, including nils, survived the upgrade`);
}
