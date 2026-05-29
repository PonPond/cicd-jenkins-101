# syntax=docker/dockerfile:1

# --- deps: production-only node_modules ---
FROM node:20-bookworm-slim AS deps
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci --omit=dev

# --- build: full deps, lint + test as a build gate ---
FROM node:20-bookworm-slim AS build
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci
COPY . .
RUN npm run lint && npm test

# --- runtime: distroless, non-root, minimal surface ---
FROM gcr.io/distroless/nodejs20-debian12 AS runtime
WORKDIR /app
ENV NODE_ENV=production
COPY --from=deps /app/node_modules ./node_modules
COPY src ./src
COPY package.json ./
USER nonroot
EXPOSE 3000
CMD ["src/server.js"]
