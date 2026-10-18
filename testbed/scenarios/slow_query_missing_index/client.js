import http from "k6/http";

const RATE = Number(__ENV.RATE || 8);
export const options = {
  scenarios: { s: { executor: "constant-arrival-rate", rate: RATE, timeUnit: "1s", duration: "24h", preAllocatedVUs: 20, maxVUs: 200 } },
};

// account-page traffic: order history lookups by customer
export default function () {
  http.get(`http://frontend:3000/customers/${1 + Math.floor(Math.random() * 5000)}/orders`, {
    timeout: "10s",
    headers: { "x-session-id": `s-${1 + Math.floor(Math.random() * 200)}`, "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0) shop-web/2.4" },
  });
}
