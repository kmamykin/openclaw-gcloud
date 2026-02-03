version: '3.8'

services:
  openclaw-gateway:
    image: ${REGISTRY}/openclaw-cloud:latest
    container_name: openclaw-gateway
    restart: unless-stopped
    env_file: .env
    environment:
      - HOME=/home/node
      - TERM=xterm-256color
      - OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_GATEWAY_TOKEN}
      - OPENCLAW_GATEWAY_PORT=${OPENCLAW_GATEWAY_PORT}
      - OPENCLAW_GATEWAY_BIND=${OPENCLAW_GATEWAY_BIND}
      - NODE_OPTIONS=--max-old-space-size=${NODE_MAX_OLD_SPACE_SIZE}
      - ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
      - OPENAI_API_KEY=${OPENAI_API_KEY}
    volumes:
      - /home/${GCP_VM_USER}/.openclaw:/home/node/.openclaw
      - /home/${GCP_VM_USER}/.openclaw/workspace:/home/node/.openclaw/workspace
    ports:
      - "127.0.0.1:${OPENCLAW_GATEWAY_PORT}:${OPENCLAW_GATEWAY_PORT}"
    deploy:
      resources:
        limits:
          cpus: '${DOCKER_CPU_LIMIT}'
          memory: ${DOCKER_MEMORY_LIMIT}
        reservations:
          cpus: '1.0'
          memory: ${DOCKER_MEMORY_RESERVATION}
    init: true
    command:
      [
        "node",
        "dist/index.js",
        "gateway",
        "--bind",
        "${OPENCLAW_GATEWAY_BIND}",
        "--port",
        "${OPENCLAW_GATEWAY_PORT}",
      ]

  openclaw-cli:
    image: ${REGISTRY}/openclaw-cloud:latest
    container_name: openclaw-cli
    environment:
      - HOME=/home/node
      - TERM=xterm-256color
      - BROWSER=echo
      - OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_GATEWAY_TOKEN}
      - ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
      - OPENAI_API_KEY=${OPENAI_API_KEY}
    volumes:
      - /home/${GCP_VM_USER}/.openclaw:/home/node/.openclaw
      - /home/${GCP_VM_USER}/.openclaw/workspace:/home/node/.openclaw/workspace
    stdin_open: true
    tty: true
    init: true
    entrypoint: ["node", "dist/index.js"]
    profiles: ["cli"]  # Only run when explicitly invoked
