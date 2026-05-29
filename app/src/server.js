import express from 'express';
import client from 'prom-client';

const DEFAULT_PORT = 3000;
const SHUTDOWN_TIMEOUT_MS = 10_000;

const register = new client.Registry();
client.collectDefaultMetrics({ register });

const httpRequestDuration = new client.Histogram({
  name: 'http_request_duration_seconds',
  help: 'HTTP request duration in seconds',
  labelNames: ['method', 'route', 'status'],
  buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5],
});
register.registerMetric(httpRequestDuration);

export function createApp() {
  const app = express();
  app.use(express.json());

  // Readiness is toggled off during shutdown so the load balancer drains
  // traffic before the server stops accepting connections.
  const state = { ready: true };
  app.locals.setReady = (value) => {
    state.ready = value;
  };

  app.use((req, res, next) => {
    const endTimer = httpRequestDuration.startTimer();
    res.on('finish', () => {
      // Use the matched route (not raw path) to keep metric cardinality bounded.
      const route = req.route?.path ?? 'unmatched';
      endTimer({ method: req.method, route, status: res.statusCode });
    });
    next();
  });

  app.get('/healthz', (req, res) => res.status(200).json({ status: 'ok' }));

  app.get('/readyz', (req, res) =>
    state.ready
      ? res.status(200).json({ status: 'ready' })
      : res.status(503).json({ status: 'draining' })
  );

  app.get('/metrics', async (req, res) => {
    res.set('Content-Type', register.contentType);
    res.end(await register.metrics());
  });

  app.get('/api/hello', (req, res) => {
    const name = String(req.query.name ?? 'world');
    res.json({ message: `hello, ${name}` });
  });

  app.post('/api/echo', (req, res) => {
    res.status(200).json({ youSent: req.body ?? null });
  });

  app.use((req, res) => res.status(404).json({ error: 'not found' }));

  return app;
}

function startServer() {
  const port = Number(process.env.PORT ?? DEFAULT_PORT);
  const app = createApp();
  const server = app.listen(port, () => {
    console.log(JSON.stringify({ level: 'info', msg: 'listening', port }));
  });

  const shutdown = (signal) => {
    console.log(JSON.stringify({ level: 'info', msg: 'shutting down', signal }));
    app.locals.setReady(false); // fail readiness so traffic drains first
    server.close(() => process.exit(0));
    setTimeout(() => process.exit(1), SHUTDOWN_TIMEOUT_MS).unref();
  };

  process.on('SIGTERM', () => shutdown('SIGTERM'));
  process.on('SIGINT', () => shutdown('SIGINT'));
}

const isMain = import.meta.url === `file://${process.argv[1]}`;
if (isMain) {
  startServer();
}
