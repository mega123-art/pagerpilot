const express = require("express");
const promClient = require("prom-client");

const app = express();
const port = process.env.PORT || 3000;

const register = new promClient.Registry();
promClient.collectDefaultMetrics({ register });

const httpRequests = new promClient.Counter({
  name: "demo_api_http_requests_total",
  help: "Total HTTP requests received by the demo API",
  labelNames: ["method", "route", "status"],
  registers: [register],
});

app.use((req, res, next) => {
  res.on("finish", () => {
    const route = req.route?.path || req.path;
    httpRequests.inc({
      method: req.method,
      route,
      status: String(res.statusCode),
    });
    console.log(JSON.stringify({
      level: "info",
      message: "http_request",
      method: req.method,
      path: req.path,
      status: res.statusCode,
    }));
  });
  next();
});

app.get("/health", (_req, res) => {
  res.json({ status: "ok" });
});

app.get("/metrics", async (_req, res) => {
  res.set("Content-Type", register.contentType);
  res.end(await register.metrics());
});

app.listen(port, "0.0.0.0", () => {
  console.log(`demo-api listening on port ${port}`);
});
