// Lance node --test sur lib/**/*.test.js (unit) ou lib/**/*.int.test.js (int).
const { readdirSync, statSync } = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const kind = process.argv[2]; // "unit" | "int"
function walk(dir) {
  return readdirSync(dir).flatMap((f) => {
    const p = path.join(dir, f);
    return statSync(p).isDirectory() ? walk(p) : [p];
  });
}
const files = walk(path.join(__dirname, "..", "lib")).filter((f) =>
  kind === "int" ? f.endsWith(".int.test.js") :
    f.endsWith(".test.js") && !f.endsWith(".int.test.js"));
if (files.length === 0) {
  console.log(`Aucun test ${kind}.`);
  process.exit(0);
}
const r = spawnSync(process.execPath, ["--test", ...files], { stdio: "inherit" });
process.exit(r.status ?? 1);
