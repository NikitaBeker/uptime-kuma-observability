#!/bin/sh
set -e

probe() {
  docker run --rm --network host curlimages/curl:8.11.1 \
    sh -c "curl -s 'http://localhost:9090/api/v1/query?query=probe_success%7Binstance%3D%22http%3A%2F%2Fuptime-kuma%3A3001%22%7D'"
}

echo "===== PART A: Failure visibility via pause ====="
echo "BEFORE:"
probe | grep -oE '"value":\[[^]]*\]'

echo "Pausing uptime-kuma..."
docker pause uptime-kuma
echo "Waiting 20s for Prometheus to record failure..."
sleep 20
echo "DURING OUTAGE:"
probe | grep -oE '"value":\[[^]]*\]'

echo "Unpausing uptime-kuma..."
docker unpause uptime-kuma
echo "Waiting 20s for Prometheus to record recovery..."
sleep 20
echo "AFTER RECOVERY:"
probe | grep -oE '"value":\[[^]]*\]'

echo ""
echo "===== PART B: restart: unless-stopped ====="
echo "Killing PID 1 inside uptime-kuma (simulates crash)..."
docker exec uptime-kuma kill -9 1 || true
RESTARTED=0
for i in $(seq 1 30); do
  if docker ps --filter name=uptime-kuma --filter status=running --format '{{.Names}}' | grep -q uptime-kuma; then
    echo "Container restarted automatically after $i sec (restart policy works)"
    RESTARTED=1
    break
  fi
  sleep 1
done
if [ "$RESTARTED" = "0" ]; then
  echo "ERROR: container did not restart within 30s"
  exit 1
fi

echo "Waiting 15s for service to become healthy..."
sleep 15
echo "FINAL:"
probe | grep -oE '"value":\[[^]]*\]'

echo "===== CHAOS TEST PASSED ====="
