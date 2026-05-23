# Build stage
FROM node:20-alpine AS builder

WORKDIR /app

COPY web/package*.json ./
RUN npm ci --only=production

COPY web/ .

# Production stage
FROM node:20-alpine AS production

RUN apk add --no-cache dumb-init

ENV NODE_ENV=production
ENV PORT=3000

WORKDIR /app

RUN addgroup -g 1000 appgroup && adduser -u 1000 -G appgroup -s /bin/sh -D appuser

COPY --from=builder --chown=appuser:appgroup /app/node_modules ./node_modules
COPY --chown=appuser:appgroup web/ .

USER appuser

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
  CMD wget -qO- http://localhost:3000/health || exit 1

ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "./bin/www"]
