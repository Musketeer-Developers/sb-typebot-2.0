# Stage 1: Base image
FROM node:18-bullseye-slim AS base
WORKDIR /app
ARG SCOPE
ENV SCOPE=${SCOPE}
RUN npm --global install pnpm

# Stage 2: Pruner stage
FROM base AS pruner
RUN npm --global install turbo
WORKDIR /app
COPY . .
RUN echo "Debugging: SCOPE is ${SCOPE}"
RUN turbo prune --scope=${SCOPE} --docker
RUN echo "Debugging: After turbo prune"

# Stage 3: Builder stage
FROM base AS builder
RUN apt-get -qy update && apt-get -qy --no-install-recommends install openssl git
WORKDIR /app
COPY .gitignore .gitignore
COPY .npmrc .pnpmfile.cjs ./
COPY --from=pruner /app/out/json/ .
COPY --from=pruner /app/out/pnpm-lock.yaml ./pnpm-lock.yaml
RUN pnpm install
COPY --from=pruner /app/out/full/ .
COPY turbo.json turbo.json

RUN pnpm turbo run build:docker --filter=${SCOPE}...

# Stage 4: Runner stage
FROM base AS runner
WORKDIR /app
ENV NODE_ENV production
RUN apt-get -qy update \
    && apt-get -qy --no-install-recommends install \
    openssl \
    && apt-get autoremove -yq \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*
COPY ./packages/prisma ./packages/prisma
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/apps/${SCOPE}/public ./apps/${SCOPE}/public
COPY --from=builder --chown=node:node /app/apps/${SCOPE}/.next/standalone ./
COPY --from=builder --chown=node:node /app/apps/${SCOPE}/.next/static ./apps/${SCOPE}/.next/static

# COPY scripts/inject-runtime-env.sh scripts/${SCOPE}-entrypoint.sh ./
RUN chmod +x ./${SCOPE}-entrypoint.sh \
    && chmod +x ./inject-runtime-env.sh
ENTRYPOINT ./${SCOPE}-entrypoint.sh

EXPOSE 3000
ENV PORT 3000
