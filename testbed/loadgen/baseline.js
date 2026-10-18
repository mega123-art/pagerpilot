import http from "k6/http";

const TARGET = __ENV.TARGET || "http://frontend:3000";
const RATE = Number(__ENV.RATE || 8);

// Open loop: arrivals are scheduled at a fixed rate whether or not earlier
// requests finished, so a slow service doesn't get relief from the generator.
export const options = {
  scenarios: {
    baseline: {
      executor: "constant-arrival-rate",
      rate: RATE,
      timeUnit: "1s",
      duration: "24h",
      preAllocatedVUs: 20,
      maxVUs: 200,
    },
  },
};

const rand = (n) => 1 + Math.floor(Math.random() * n);

export default function () {
  const params = {
    timeout: "10s",
    headers: {
      "User-Agent": "Mozilla/5.0 (X11; Linux aarch64) shop-web/2.4",
      "x-session-id": `s-${rand(200)}`,
    },
    tags: { name: "req" },
  };
  const r = Math.random();
  if (r < 0.3) http.get(`${TARGET}/checkout`, params);
  else if (r < 0.7) http.get(`${TARGET}/orders/${rand(500000)}`, params);
  else http.get(`${TARGET}/customers/${rand(5000)}/orders`, params);
}
