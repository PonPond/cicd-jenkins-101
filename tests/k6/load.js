import http from 'k6/http';
import { check, sleep } from 'k6';
import { thresholds, stages, BASE_URL } from './lib/options.js';

// Load: ramp to 50 VUs. Thresholds act as the deploy gate — k6 exits
// non-zero if p95 latency or error rate break the SLO, failing the pipeline.
export const options = {
  stages: stages.load,
  thresholds,
};

export default function () {
  const res = http.get(`${BASE_URL}/api/hello?name=load`);
  check(res, {
    'status is 200': (r) => r.status === 200,
  });
  sleep(0.5);
}
