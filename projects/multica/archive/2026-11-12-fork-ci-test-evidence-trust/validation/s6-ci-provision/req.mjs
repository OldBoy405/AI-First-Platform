import { createRequire } from "node:module";
const require = createRequire(import.meta.url);
try { const pg = require("pg"); console.log("createRequire OK", typeof pg.Client); }
catch (e) { console.log("createRequire FAILED", e.code); }
