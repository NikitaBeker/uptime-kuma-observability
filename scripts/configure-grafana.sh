#!/bin/sh
set -e

AUTH="admin:GrafanaSecret_2026!"
GRAFANA="http://localhost:3000"

echo "=== Waiting for Grafana to be ready ==="
READY=0
for i in $(seq 1 30); do
  if docker run --rm --network host curlimages/curl:8.11.1 sh -c \
      "curl -sf 'http://localhost:3000/api/health' >/dev/null" 2>/dev/null; then
    echo "Grafana ready after $i sec"
    READY=1
    break
  fi
  sleep 1
done
if [ "$READY" = "0" ]; then
  echo "ERROR: Grafana did not become ready in 30s"
  exit 1
fi

echo "=== Creating Prometheus datasource ==="
docker run --rm --network host curlimages/curl:8.11.1 sh -c \
  "curl -sf -X POST '$GRAFANA/api/datasources' -u '$AUTH' -H 'Content-Type: application/json' -d '{\"name\":\"Prometheus\",\"type\":\"prometheus\",\"url\":\"http://prometheus:9090\",\"access\":\"proxy\",\"isDefault\":true}' && echo created || echo exists"

echo "=== Importing dashboard ==="
docker run --rm -i --network host curlimages/curl:8.11.1 sh -c \
  "curl -sf -X POST '$GRAFANA/api/dashboards/db' -u '$AUTH' -H 'Content-Type: application/json' -d @-" <<'DASH_EOF'
{
  "dashboard": {
    "title": "Uptime Kuma Health",
    "tags": ["safeboard", "uptime"],
    "timezone": "browser",
    "panels": [
      {"id":1,"title":"MariaDB UP","type":"stat","gridPos":{"h":6,"w":6,"x":0,"y":0},"targets":[{"expr":"mysql_up","refId":"A"}]},
      {"id":2,"title":"Uptime Kuma Probe","type":"stat","gridPos":{"h":6,"w":6,"x":6,"y":0},"targets":[{"expr":"probe_success{instance=\"http://uptime-kuma:3001\"}","refId":"A"}]},
      {"id":3,"title":"Uptime Kuma Latency (s)","type":"timeseries","gridPos":{"h":8,"w":12,"x":12,"y":0},"targets":[{"expr":"probe_duration_seconds{instance=\"http://uptime-kuma:3001\"}","refId":"A"}]},
      {"id":4,"title":"Container CPU (cores)","type":"timeseries","gridPos":{"h":8,"w":12,"x":0,"y":8},"targets":[{"expr":"sum(rate(container_cpu_usage_seconds_total{name=~\".+\"}[5m])) by (name)","refId":"A"}]},
      {"id":5,"title":"Container RAM (bytes)","type":"timeseries","gridPos":{"h":8,"w":12,"x":12,"y":8},"targets":[{"expr":"container_memory_usage_bytes{name=~\".+\"}","refId":"A"}]}
    ]
  },
  "overwrite": true
}
DASH_EOF
echo ""
echo "=== Done ==="
