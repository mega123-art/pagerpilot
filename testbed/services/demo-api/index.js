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

const httpDuration = new promClient.Histogram({
  name: "demo_api_http_request_duration_seconds",
  help: "HTTP request latency in seconds",
  labelNames: ["method", "route", "status"],
  buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5],
  registers: [register],
});

const SERVICE = process.env.SERVICE_NAME || "demo-api";
// Fault switch: "" | "latency" | "errors"
const FAULT = process.env.FAULT_MODE || "";
const QUIET_ROUTES = new Set(["/health", "/metrics"]);

app.use((req, res, next) => {
  const start = process.hrtime.bigint();
  res.on("finish", () => {
    // unmatched requests share one label value: bounded cardinality
    const route = req.route?.path || "unmatched";
    const labels = { method: req.method, route, status: String(res.statusCode) };
    httpRequests.inc(labels);
    httpDuration.observe(labels, Number(process.hrtime.bigint() - start) / 1e9);
    if (QUIET_ROUTES.has(req.path)) return; // probe/scrape chatter
    console.log(JSON.stringify({
      time: new Date().toISOString(),
      level: res.statusCode >= 500 ? "error" : "info",
      service: SERVICE,
      message: "http_request",
      method: req.method,
      path: req.path,
      status: res.statusCode,
    }));
  });
  next();
});

app.use(async (_req, res, next) => {
  if (FAULT === "latency") await new Promise((r) => setTimeout(r, 1500));
  if (FAULT === "errors" && Math.random() < 0.5) {
    return res.status(500).json({ error: "injected fault" });
  }
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
