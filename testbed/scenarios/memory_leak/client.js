import http from "k6/http";

const RATE = Number(__ENV.RATE || 12);
export const options = {
  scenarios: { s: { executor: "constant-arrival-rate", rate: RATE, timeUnit: "1s", duration: "24h", preAllocatedVUs: 20, maxVUs: 200 } },
};

// every visitor arrives with a fresh session id
export default function () {
  const sid = `u-${__VU}-${__ITER}-${Math.random().toString(36).slice(2, 10)}`;
  http.get(`http://frontend:3000/customers/${1 + Math.floor(Math.random() * 5000)}/orders`, {
    timeout: "10s",
    headers: { "x-session-id": sid, "User-Agent": "Mozilla/5.0 (Windows NT 10.0) shop-web/2.4" },
  });
}
