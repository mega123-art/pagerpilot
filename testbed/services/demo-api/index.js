const express = require("express");
const { setup, log } = require("../_shared");

const app = express();
const port = process.env.PORT || 3000;

// Work duration range. Ordinary tuning knobs, read per request inside the handler.
const workMinMs = Number(process.env.WORK_MIN_MS || 10);
const workMaxMs = Number(process.env.WORK_MAX_MS || 100);

setup(app);

app.get("/work", async (_req, res) => {
  const ms = workMinMs + Math.random() * (workMaxMs - workMinMs);
  await new Promise((r) => setTimeout(r, ms));
  res.json({ status: "ok" });
});

app.listen(port, "0.0.0.0", () => log("info", `listening on port ${port}`));
