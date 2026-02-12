#!/bin/bash

# Dr. Medhat Clinic - Stop Script
# Double-click this file to stop the clinic system

cd "$(dirname "$0")"

echo ""
echo "Stopping Dr. Medhat Clinic System..."
echo ""

if [ -f ".server.pid" ]; then
    PID=$(cat .server.pid)
    if ps -p $PID > /dev/null 2>&1; then
        kill $PID 2>/dev/null
        rm -f .server.pid
        echo "✓ Server stopped successfully."
    else
        rm -f .server.pid
        echo "Server was not running."
    fi
else
    # Try to find and kill uvicorn process
    pkill -f "uvicorn app.main:app" 2>/dev/null
    echo "✓ Server stopped."
fi

echo ""
