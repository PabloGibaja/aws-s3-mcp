# Build stage
FROM node:20-alpine AS builder

# Set working directory
WORKDIR /app

# Install build dependencies
RUN apk add --no-cache --virtual .build-deps python3 make g++

# Copy package.json and package-lock.json separately (for better cache optimization)
COPY package.json ./
COPY package-lock.json ./

# Install dependencies needed for build
RUN npm ci --ignore-scripts && \
    npm cache clean --force

# Copy source code
COPY tsconfig.json ./
COPY src/ ./src/

# Build the application
RUN npm run build

# Runtime stage
FROM node:20-alpine AS runner

# Set working directory
WORKDIR /app

# Create non-root user
RUN addgroup -S nodegroup && \
    adduser -S nodeuser -G nodegroup

# Copy package files
COPY package.json ./
COPY package-lock.json ./

# Install production dependencies only
RUN npm ci --omit=dev --ignore-scripts && \
    npm cache clean --force

# Copy built files from builder stage
COPY --from=builder /app/dist ./dist/

# Create healthcheck script
COPY --chown=nodeuser:nodegroup <<EOF /app/healthcheck.sh
#!/bin/sh
if [ -f /app/dist/index.js ]; then
  exit 0
else
  exit 1
fi
EOF

# Create entrypoint script that can run HTTP server or keep container alive
RUN printf '#!/bin/sh\nif [ "$1" = "http" ]; then\n  echo "Starting HTTP MCP Server on port ${PORT:-3000}..."\n  exec node dist/index.js --http\nelse\n  echo "AWS S3 MCP Server container started. Use docker exec to run commands."\n  echo "For MCP Inspector, use: ./run-inspector.sh --docker"\n  echo "For HTTP server, use: docker run with http argument"\n  exec tail -f /dev/null\nfi\n' > /app/entrypoint.sh && \
    chmod +x /app/entrypoint.sh && \
    chmod +x /app/healthcheck.sh && \
    chown -R nodeuser:nodegroup /app

# Set default environment variables
ENV NODE_ENV=production \
    AWS_REGION=us-east-1 \
    S3_MAX_BUCKETS=5

# Configure healthcheck
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 CMD ["/app/healthcheck.sh"]

# Switch to non-root user
USER nodeuser

EXPOSE 3000

# Set entrypoint
ENTRYPOINT ["/app/entrypoint.sh"]
