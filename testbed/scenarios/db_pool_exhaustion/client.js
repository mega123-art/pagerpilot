import http from "k6/http";

const RATE = Number(__ENV.RATE || 4);
export const options = {
  scenarios: { s: { executor: "constant-arrival-rate", rate: RATE, timeUnit: "1s", duration: "24h", preAllocatedVUs: 50, maxVUs: 300 } },
};

// nightly-style reporting client calling the export endpoint directly
export default function () {
  http.post("http://orders:3001/reports/export", null, {
    timeout: "15s",
    headers: { "User-Agent": "report-sync/3.1" },
  });
}
