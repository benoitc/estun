#!/bin/bash
set -e

cd "$(dirname "$0")/../.."

echo "=== Building estun ==="
rebar3 compile

echo ""
echo "=== Building Docker images ==="
cd examples/docker_p2p
docker-compose build

echo ""
echo "=== Running P2P test ==="
docker-compose up --abort-on-container-exit

echo ""
echo "=== Cleaning up ==="
docker-compose down
