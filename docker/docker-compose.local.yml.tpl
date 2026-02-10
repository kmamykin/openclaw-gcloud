services:
  openclaw-gateway:
    image: openclaw-cloud:latest
    container_name: openclaw-gateway-local
    restart: "no"
    ports:
      - "18789:18789"
    env_file:
      - .openclaw/.env
    environment:
      - HOME=/home/node
      - TERM=xterm-256color
      - NODE_OPTIONS=--max-old-space-size=${NODE_MAX_OLD_SPACE_SIZE:-2560}
      - OPENCLAW_GATEWAY_BIND=lan
    volumes:
      - ./.openclaw:/home/node/.openclaw
${WORKSPACE_VOLUMES}
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
        "18789",
        "--allow-unconfigured",
      ]

  openclaw-cli:
    image: openclaw-cloud:latest
    container_name: openclaw-cli-local
    env_file:
      - .openclaw/.env
    environment:
      - HOME=/home/node
      - TERM=xterm-256color
      - BROWSER=echo
    volumes:
      - ./.openclaw:/home/node/.openclaw
${WORKSPACE_VOLUMES}
    stdin_open: true
    tty: true
    init: true
    entrypoint: ["node", "dist/index.js"]
    profiles: ["cli"]
