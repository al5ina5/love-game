# Build stage
FROM node:20-slim AS builder
WORKDIR /app
# Copy package files
COPY package*.json ./
RUN npm install
# Copy source
COPY . .
RUN npm run build

# Production stage
FROM node:20-slim
WORKDIR /app
# Install production dependencies
COPY package*.json ./
RUN npm install --omit=dev
# Copy compiled code from builder
COPY --from=builder /app/dist ./dist

# Railway uses the PORT env var automatically for HTTP
# We also want to expose our TCP port
EXPOSE 3000
EXPOSE 12346

# Start the server directly using node
CMD ["node", "dist/index.js"]
