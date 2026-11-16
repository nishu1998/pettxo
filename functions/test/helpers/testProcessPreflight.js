"use strict";

// Loaded through NODE_OPTIONS=--require by scripts/run_tests.js into every
// test process. Aborts the process before any test code runs if Google
// credentials are reachable, a project is not demo-*, or an emulator host is
// not loopback.
const {assertTestProcessPreflight} = require("./firebaseTestSafety");

try {
  assertTestProcessPreflight(process.env);
} catch (error) {
  process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
  process.exit(1);
}
