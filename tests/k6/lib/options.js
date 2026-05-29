// Shared k6 config so every scenario enforces the same SLOs.
export const thresholds = {
  http_req_duration: ['p(95)<200', 'p(99)<500'], // latency budget (ms)
  http_req_failed: ['rate<0.01'], // < 1% errors
  checks: ['rate>0.99'], // > 99% of assertions pass
};

export const stages = {
  smoke: [{ duration: '30s', target: 1 }],
  load: [
    { duration: '30s', target: 20 }, // ramp up
    { duration: '1m', target: 50 }, // sustained load
    { duration: '30s', target: 0 }, // ramp down
  ],
  stress: [
    { duration: '1m', target: 100 },
    { duration: '2m', target: 200 },
    { duration: '1m', target: 0 },
  ],
};

export const BASE_URL = __ENV.BASE_URL || 'http://localhost:3000';
