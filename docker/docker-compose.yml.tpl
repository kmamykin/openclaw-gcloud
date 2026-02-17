services:
  openclaw-gateway:
    image: ${REGISTRY}/openclaw-cloud:latest
    container_name: openclaw-gateway
    restart: unless-stopped
    ports:
      - "127.0.0.1:${OPENCLAW_GATEWAY_PORT}:${OPENCLAW_GATEWAY_PORT}"
    env_file:
      - .openclaw/.env
    environment:
      - HOME=/home/node
      - TERM=xterm-256color
      - NODE_OPTIONS=--max-old-space-size=${NODE_MAX_OLD_SPACE_SIZE}
    volumes:
      - /home/${GCP_VM_USER}/openclaw/.openclaw:/home/node/.openclaw
      - /home/${GCP_VM_USER}/openclaw/workspaces:/home/node/workspaces
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
        "run",
        "--bind",
        "lan",
        "--port",
        "${OPENCLAW_GATEWAY_PORT}",
        "--allow-unconfigured",
      ]

  openclaw-cli:
    image: ${REGISTRY}/openclaw-cloud:latest
    container_name: openclaw-cli
    env_file:
      - .openclaw/.env
    environment:
      - HOME=/home/node
      - TERM=xterm-256color
      - BROWSER=echo
    volumes:
      - /home/${GCP_VM_USER}/openclaw/.openclaw:/home/node/.openclaw
      - /home/${GCP_VM_USER}/openclaw/workspaces:/home/node/workspaces
    stdin_open: true
    tty: true
    init: true
    entrypoint: ["node", "dist/index.js"]
    profiles: ["cli"]  # Only run when explicitly invoked
