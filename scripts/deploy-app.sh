#!/bin/sh
set -e
docker network create uptime-monitor-net 2>/dev/null || true
docker compose -f docker-compose.app.yml up -d
