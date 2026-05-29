import http from 'k6/http';
import { check, sleep } from 'k6';
import { stages, BASE_URL } from './lib/options.js';

// Stress: push to 200 VUs to find the breaking point. Run manually, not as a
// gate — relaxed thresholds because the goal is to observe degradation, not pass.
export const options = {
  stages: stages.stress,
  thresholds: {
    http_req_failed: ['rate<0.10'], // tolerate up to 10% errors under stress
  },
};

export default function () {
  const res = http.get(`${BASE_URL}/api/hello?name=stress`);
  check(res, { 'status is 200': (r) => r.status === 200 });
  sleep(0.2);
}
