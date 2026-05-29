import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { createApp } from '../src/server.js';

let server;
let baseUrl;

before(async () => {
  await new Promise((resolve) => {
    server = createApp().listen(0, () => {
      const { port } = server.address();
      baseUrl = `http://127.0.0.1:${port}`;
      resolve();
    });
  });
});

after(() => server?.close());

test('GET /healthz returns ok', async () => {
  const res = await fetch(`${baseUrl}/healthz`);
  assert.equal(res.status, 200);
  assert.equal((await res.json()).status, 'ok');
});

test('GET /readyz reports readiness', async () => {
  const res = await fetch(`${baseUrl}/readyz`);
  assert.equal(res.status, 200);
  assert.equal((await res.json()).status, 'ready');
});

test('GET /metrics exposes prometheus metrics', async () => {
  const res = await fetch(`${baseUrl}/metrics`);
  assert.equal(res.status, 200);
  assert.match(await res.text(), /http_request_duration_seconds/);
});

test('GET /api/hello greets with the query name', async () => {
  const res = await fetch(`${baseUrl}/api/hello?name=pond`);
  assert.equal(res.status, 200);
  assert.equal((await res.json()).message, 'hello, pond');
});

test('GET /api/hello defaults to world', async () => {
  const res = await fetch(`${baseUrl}/api/hello`);
  assert.equal((await res.json()).message, 'hello, world');
});

test('POST /api/echo returns the payload', async () => {
  const res = await fetch(`${baseUrl}/api/echo`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ a: 1 }),
  });
  assert.equal(res.status, 200);
  assert.deepEqual((await res.json()).youSent, { a: 1 });
});

test('unknown route returns 404', async () => {
  const res = await fetch(`${baseUrl}/nope`);
  assert.equal(res.status, 404);
});
