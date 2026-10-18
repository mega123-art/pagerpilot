const express = require("express");
const { log } = require("../_shared");

const app = express();
app.use(express.json({ limit: "1mb" }));
app.get("/health", (_req, res) => res.json({ status: "ok" }));
app.post("/", (req, res) => {
  log("info", "alert webhook received", { payload: req.body });
  res.sendStatus(200);
});
app.listen(process.env.PORT || 8080, "0.0.0.0", () => log("info", "listening"));
