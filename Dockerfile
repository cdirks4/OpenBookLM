# Base image
FROM node:20-slim AS base

# Add build arguments for Clerk keys
ARG NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY
ARG CLERK_SECRET_KEY

# Set environment variables
ENV NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY=$NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY
ENV CLERK_SECRET_KEY=$CLERK_SECRET_KEY

# Install OpenSSL and other required dependencies
RUN apt-get update -y && apt-get install -y openssl libssl-dev ca-certificates

# Install pnpm
RUN npm install -g pnpm

# Install dependencies only when needed
FROM base AS deps
WORKDIR /app

# Install dependencies for Prisma and other builds
RUN apt-get update && \
    apt-get install -y openssl python3 make g++

# Copy package files
COPY package.json ./
COPY pnpm-lock.yaml ./
COPY prisma ./prisma/

# Clean install dependencies
RUN pnpm install --frozen-lockfile

# Development image
FROM base AS development
WORKDIR /app

COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Generate Prisma Client for development
RUN npx prisma generate

COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh
# Expose port
EXPOSE 3000

# Start development server
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["pnpm", "dev"]

# Rebuild the source code only when needed
FROM base AS builder
WORKDIR /app

COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Set environment variables for build
ENV NEXT_TELEMETRY_DISABLED 1
ENV NODE_ENV production

# Generate Prisma Client
RUN npx prisma generate

# Build application with --no-lint flag to skip linting
RUN pnpm run build --no-lint

# Production image, copy all the files and run next
FROM base AS runner
WORKDIR /app

ENV NODE_ENV production
ENV NEXT_TELEMETRY_DISABLED 1

# Create system user
RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs

# Install production dependencies
COPY --from=builder /app/package.json ./package.json
COPY --from=builder /app/pnpm-lock.yaml ./pnpm-lock.yaml
COPY --from=builder /app/next.config.mjs ./
COPY --from=builder /app/public ./public
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static
COPY --from=builder /app/prisma ./prisma

# Install only production dependencies
RUN pnpm install --prod

# Set permissions
RUN chown -R nextjs:nodejs .

USER nextjs

EXPOSE 3000

ENV PORT 3000
ENV HOSTNAME "0.0.0.0"

CMD ["pnpm", "start"] 