# Build stage
FROM node:20-alpine AS builder

WORKDIR /app

COPY api/package*.json ./
RUN npm ci --only=production

COPY api/ .

# Production stage
FROM node:20-alpine AS production

RUN apk add --no-cache dumb-init

ENV NODE_ENV=production
ENV PORT=4000

WORKDIR /app

COPY --from=builder --chown=node:node /app/node_modules ./node_modules
COPY --chown=node:node api/ .

USER node

EXPOSE 4000

HEALTHCHECK --interval=30s --timeout=10s --start-period=20s --retries=3 \
  CMD wget -qO- http://localhost:4000/health || exit 1

ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "./bin/www"]
