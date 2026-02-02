#!/bin/bash
set -e

# Script to manually fix OpenClaw gateway service on existing VM
# This applies the fixes from the updated startup script template

echo "=================================="
echo "Fixing OpenClaw Gateway Service"
echo "Started at: $(date)"
echo "=================================="

# 1. Create openclaw config
echo "Step 1: Creating openclaw configuration..."
sudo -u node bash -c '
export HOME=/home/node
mkdir -p /home/node/.openclaw/workspace

cat > /home/node/.openclaw/openclaw.json << "EOF"
{
  "gateway": {
    "auth": {
      "token": "REDACTED_TOKEN"
    },
    "port": 18789,
    "bind": "loopback"
  }
}
EOF

chmod 600 /home/node/.openclaw/openclaw.json
'

echo "✓ OpenClaw configuration created"

# 2. Fix systemd service ExecStart
echo ""
echo "Step 2: Fixing systemd service ExecStart..."
sudo sed -i 's|ExecStart=/usr/bin/openclaw gateway start|ExecStart=/usr/bin/openclaw gateway|' /etc/systemd/system/openclaw-gateway.service

echo "✓ Systemd service updated"

# 3. Reload and restart service
echo ""
echo "Step 3: Reloading and restarting service..."
sudo systemctl daemon-reload
sudo systemctl enable openclaw-gateway
sudo systemctl restart openclaw-gateway

echo "✓ Service restarted"

# 4. Wait for service to start
echo ""
echo "Waiting 5 seconds for service to start..."
sleep 5

# 5. Check service status
echo ""
echo "Step 4: Checking service status..."
if sudo systemctl is-active --quiet openclaw-gateway; then
    echo "✓ OpenClaw gateway service is running"
    echo ""
    sudo systemctl status openclaw-gateway --no-pager -l
else
    echo "✗ OpenClaw gateway service failed to start"
    echo ""
    echo "Recent logs:"
    sudo journalctl -u openclaw-gateway -n 50 --no-pager
    exit 1
fi

# 6. Verify port listening
echo ""
echo "Step 5: Verifying port is listening..."
if sudo ss -tulpn | grep -q 18789; then
    echo "✓ Gateway is listening on port 18789"
    sudo ss -tulpn | grep 18789
else
    echo "✗ Gateway is not listening on port 18789"
fi

# 7. Check if enabled for auto-start
echo ""
echo "Step 6: Verifying auto-start on boot..."
if sudo systemctl is-enabled --quiet openclaw-gateway; then
    echo "✓ Service is enabled for auto-start on boot"
else
    echo "✗ Service is not enabled for auto-start"
fi

echo ""
echo "=================================="
echo "Fix completed successfully!"
echo "Completed at: $(date)"
echo "=================================="
echo ""
echo "To test the gateway:"
echo "1. In a new terminal, run: cd terraform && ./scripts/ssh.sh forward"
echo "2. In another terminal, run: curl http://localhost:18789/__openclaw__/canvas/"
