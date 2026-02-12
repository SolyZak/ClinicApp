#!/bin/bash

# Dr. Medhat Clinic - Start Script
# Double-click this file to start the clinic system

cd "$(dirname "$0")"
APP_DIR="$(pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo ""
echo "============================================"
echo "   Dr. Medhat - Patient Management System"
echo "============================================"
echo ""

# Check for Python 3
if command -v python3 &> /dev/null; then
    PYTHON=python3
elif command -v python &> /dev/null; then
    PYTHON=python
else
    echo -e "${RED}❌ Python is not installed!${NC}"
    echo ""
    echo "Please install Python 3.9 or newer from:"
    echo "https://www.python.org/downloads/"
    echo ""
    echo "After installing, run this script again."
    echo ""
    read -p "Press Enter to close..."
    exit 1
fi

# Check Python version
PY_VERSION=$($PYTHON -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
echo "✓ Found Python $PY_VERSION"

# Create virtual environment if it doesn't exist
if [ ! -d "venv" ]; then
    echo ""
    echo -e "${YELLOW}First time setup - this will take about 1 minute...${NC}"
    echo "Creating virtual environment..."
    $PYTHON -m venv venv
    
    echo "Installing required packages..."
    source venv/bin/activate
    pip install --upgrade pip -q
    pip install -r requirements.txt -q
    echo -e "${GREEN}✓ Setup complete!${NC}"
else
    source venv/bin/activate
fi

# Check if server is already running
if [ -f ".server.pid" ]; then
    OLD_PID=$(cat .server.pid)
    if ps -p $OLD_PID > /dev/null 2>&1; then
        echo ""
        echo -e "${YELLOW}Server is already running!${NC}"
        echo "Opening browser..."
        sleep 1
        open "http://localhost:8000"
        exit 0
    fi
fi

# Start the server
echo ""
echo "Starting server..."
cd "$APP_DIR"
$PYTHON -m uvicorn app.main:app --host 127.0.0.1 --port 8000 &
SERVER_PID=$!
echo $SERVER_PID > .server.pid

# Wait for server to start
echo "Waiting for server to be ready..."
for i in {1..30}; do
    if curl -s http://localhost:8000/api/health > /dev/null 2>&1; then
        break
    fi
    sleep 0.5
done

# Open browser
echo ""
echo -e "${GREEN}✓ Server started successfully!${NC}"
echo ""
echo "Opening browser at http://localhost:8000"
echo ""
echo "Password: clinic123"
echo ""
sleep 1
open "http://localhost:8000"

echo "============================================"
echo "  Server is running. Keep this window open."
echo "  To stop: Close this window or run Stop.command"
echo "============================================"
echo ""

# Wait for server process
wait $SERVER_PID
