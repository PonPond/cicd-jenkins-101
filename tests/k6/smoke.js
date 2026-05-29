import http from 'k6/http';
import { check, sleep } from 'k6';
import { thresholds, stages, BASE_URL } from './lib/options.js';

// Smoke: 1 VU, quick confidence check that the deploy is alive and correct.
export const options = {
  stages: stages.smoke,
  thresholds,
};

export default function () {
  const hello = http.get(`${BASE_URL}/api/hello?name=k6`);
  check(hello, {
    'hello status is 200': (r) => r.status === 200,
    'hello body is correct': (r) => r.json('message') === 'hello, k6',
  });

  const health = http.get(`${BASE_URL}/healthz`);
  check(health, { 'healthz is 200': (r) => r.status === 200 });

  sleep(1);
}
