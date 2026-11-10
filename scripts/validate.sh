#!/bin/sh
set -e
echo "Prometheus: $(docker run --rm --network host curlimages/curl:8.11.1 sh -c 'curl -sf http://localhost:9090/-/healthy')"
echo "Grafana: $(docker run --rm --network host curlimages/curl:8.11.1 sh -c 'curl -sf http://localhost:3000/api/health | head -c 80')"
echo "Uptime Kuma: HTTP $(docker run --rm --network host curlimages/curl:8.11.1 sh -c 'curl -s -o /dev/null -w %{http_code} http://localhost:3001')"
