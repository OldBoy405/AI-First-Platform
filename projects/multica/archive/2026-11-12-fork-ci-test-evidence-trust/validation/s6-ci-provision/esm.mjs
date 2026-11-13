try { const m = await import("pg"); console.log("ESM import OK", typeof m.default.Client); }
catch (e) { console.log("ESM import FAILED", e.code); }
