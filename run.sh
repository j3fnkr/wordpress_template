#!/usr/bin/env bash

# subshell used to read .env to shell environment (so they are not set in the main shell)
(
  # Load .env into environment
  export $(grep -v '^#' .env | xargs)

  # Render Caddyfile from template
  envsubst < ./conf/Caddyfile.template > ./conf/Caddyfile
)
docker compose up -d
