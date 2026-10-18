const express = require("express");

const app = express();
app.use(express.json({ limit: "1mb" }));
app.get("/health", (_req, res) => res.json({ status: "ok" }));
app.post("/", (req, res) => {
  console.log(JSON.stringify({ time: new Date().toISOString(), level: "info", service: "alert-echo", message: "alert webhook received", payload: req.body }));
  res.sendStatus(200);
});
app.listen(process.env.PORT || 8080, "0.0.0.0");
