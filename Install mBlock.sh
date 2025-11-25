#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Switch to the directory where this script is located
cd "$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# --- 1. PRE-FLIGHT CHECKS ---

# Check if running on Linux
if [[ "$(uname -s)" != "Linux" ]]; then
    echo "Error: This installation script is only for Linux systems."
    exit 1
fi

# Check if the "resources" directory exists
if [[ ! -d "resources" ]]; then
    echo "Error: \"resources\" directory not found in $(pwd)."
    exit 1
fi

# Print installer info
echo "*********************************"
echo "mBlock Installer for Raspberry Pi"
echo "*********************************"
echo
echo "This script will install the following mBlock application and extensions."
echo "--------------------"

# Find mBlock installer
MBLOCK_DEB=$(find resources -maxdepth 1 -name "mblock*.deb" -type f -print -quit)
if [[ -n "$MBLOCK_DEB" ]]; then
    echo "mBlock: $(basename "$MBLOCK_DEB")"
else
    echo "mBlock: NOT FOUND"
    exit 1
fi

# Find extensions
echo "Extensions:"
if compgen -G "resources/*.mext" > /dev/null; then
    for ext in resources/*.mext; do
        echo " - $(basename "$ext")"
    done
else
    echo " - NONE"
fi

# Confirm installation
echo "--------------------"
echo "The full installation process will be completed in 3-4 minutes."
echo "IMPORTANT: mBlock will open during installation. Do not interact with the application window during this time. The window will close automatically when installation is complete."
echo
read -p "Do you want to proceed with the installation? (y/n): " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Installation cancelled."
    exit 0
fi

# --- 2. INSTALLATION ---

# Clear old mBlock files
echo "Removing old mBlock files..."
killall mblock &> /dev/null || true
sleep 3
sudo apt-get remove -y mblock &> /dev/null || true
rm -rf ~/mblock* ~/mlink* ~/.config/mblock

# Install new mBlock
echo "Installing mBlock package..."
sudo apt-get install "$PWD/$MBLOCK_DEB" -y --no-install-recommends &> /dev/null

# --- 3. LAUNCH & INITIALIZE ---

echo "Launching mBlock for initial setup..."
DEBUG_PORT=$(( 8000 + RANDOM % 2001 ))

# Launch mBlock with Remote Debugging enabled.
/opt/mBlock/mblock --remote-debugging-port=$DEBUG_PORT &> /dev/null &
MBLOCK_PID=$!

echo "Waiting for mBlock backend..."
# Wait for the settings file (indicates the app has created its config folder)
while [[ ! -f "$HOME/mblock/settings.json" ]]; do
    sleep 1
done

echo "Waiting for mBlock frontend..."
sleep 10

# --- 4. PYTHON WEBSOCKET INJECTOR ---

# This function embeds a Python script to talk to Chrome DevTools Protocol
run_ws_task() {
    local MODE="$1"
    local ARG1="$2" # JS Code OR File Path

    # Fetch the dynamic WebSocket URL
    WS_URL=$(curl -s "http://127.0.0.1:$DEBUG_PORT/json" | grep -oP '"webSocketDebuggerUrl": "\K[^"]+')
    
    if [ -z "$WS_URL" ]; then
        echo "Error: Could not connect to mBlock debugging interface."
        return 1
    fi

    python3 -c "
import socket, json, struct, base64, os, sys, time
from urllib.parse import urlparse

ws_url = sys.argv[1]
mode = sys.argv[2]
arg1 = sys.argv[3] 

# --- CONSTRUCT JAVASCRIPT PAYLOAD ---
if mode == 'eval':
    # Simple Execution (for LocalStorage)
    js_payload = arg1

elif mode == 'install':
    # Drag-and-Drop Simulation
    file_path = arg1
    file_name = os.path.basename(file_path)

    # 1. Create a File object.
    # 2. Use Object.defineProperty to SPOOF the 'path' property.
    #    (Electron relies on this 'path' property to know which file to copy).
    # 3. Dispatch dragenter -> dragover -> drop to the body.
    js_payload = f'''
    (function() {{
        try {{
            const filePath = '{file_path}';
            const fileName = '{file_name}';

            // Create a dummy file (content is irrelevant because we supply the path)
            const file = new File([''], fileName, {{type: ''}});

            // Force the 'path' property to point to the real Linux file
            Object.defineProperty(file, 'path', {{ value: filePath }});

            // Prepare DataTransfer
            const dataTransfer = new DataTransfer();
            dataTransfer.items.add(file);
            dataTransfer.files = dataTransfer.items; // Helper for some frameworks

            // Helper to dispatch events
            function dispatch(type) {{
                const e = new DragEvent(type, {{
                    bubbles: true,
                    cancelable: true,
                    view: window,
                    detail: 0,
                    screenX: 0, 
                    screenY: 0, 
                    clientX: window.innerWidth / 2, 
                    clientY: window.innerHeight / 2,
                    dataTransfer: dataTransfer
                }});
                
                // Target the body (standard for full-window drops)
                const target = document.body;
                target.dispatchEvent(e);
            }}

            // Execute the Drop Dance
            dispatch('dragenter');
            
            // Dragover must happen for Drop to be accepted
            dispatch('dragover');
            
            // The Drop
            dispatch('drop');

            return 'Dropped ' + fileName + ' (Path: ' + filePath + ')';
        }} catch (e) {{
            return 'JS Error: ' + e.message;
        }}
    }})()
    '''

# --- WEBSOCKET COMMUNICATION ---
parsed = urlparse(ws_url)
host = parsed.hostname or '127.0.0.1'
port = parsed.port
path = parsed.path

def create_frame(data):
    data_bytes = data.encode('utf-8')
    length = len(data_bytes)
    frame = bytearray([0x81]) # Text Opcode
    
    if length < 126: frame.append(0x80 | length)
    elif length < 65536:
        frame.append(0x80 | 126)
        frame.extend(struct.pack('!H', length))
    else:
        frame.append(0x80 | 127)
        frame.extend(struct.pack('!Q', length))
        
    mask_key = os.urandom(4)
    frame.extend(mask_key)
    masked_data = bytearray(len(data_bytes))
    for i in range(len(data_bytes)): masked_data[i] = data_bytes[i] ^ mask_key[i % 4]
    frame.extend(masked_data)
    return frame

try:
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(10)
    sock.connect((host, port))
    
    # Handshake (with Origin to satisfy security)
    key = base64.b64encode(os.urandom(16)).decode('utf-8')
    req = (f'GET {path} HTTP/1.1\r\nHost: {host}:{port}\r\nOrigin: http://{host}:{port}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n')
    sock.send(req.encode('utf-8'))
    
    # Read Handshake Response
    while b'\r\n\r\n' not in sock.recv(1024): pass

    # Send Payload
    msg = json.dumps({'id': 1, 'method': 'Runtime.evaluate', 'params': {'expression': js_payload, 'awaitPromise': True}})
    sock.send(create_frame(msg))
    
    # Read Result
    result = sock.recv(16384)
    sock.close()
except Exception as e:
    print(f'Error: {e}')
    sys.exit(1)
" "$WS_URL" "$MODE" "$ARG1"
}

# --- 5. EXECUTE TASKS ---

# Configure default device
echo "Configuring default device (Arduino Uno)..."
JS_CONFIG="localStorage.setItem('defaultDevice', JSON.stringify('arduino_uno'));"
run_ws_task "eval" "$JS_CONFIG"

# Remove privacy banner
echo "Disabling privacy banner..."
JS_CONFIG="localStorage.setItem('agreeUseAppPrivacy', 'true');"
run_ws_task "eval" "$JS_CONFIG"

# Install extensions
if compgen -G "resources/*.mext" > /dev/null; then
    for ext in resources/*.mext; do
        echo "Installing extension $(basename "$ext")..."
        
        # Get absolute path (Required for the spoofing to work)
        EXT_ABS_PATH=$(readlink -f "$ext")
        
        # Run the simulated drop
        run_ws_task "install" "$EXT_ABS_PATH"
        
        # Pause to let mBlock process the file (unzip/copy/update DB)
        sleep 3
    done
else
    echo "No extensions to install."
fi

# --- 6. CLEANUP ---

echo "Waiting for finalization..."
sleep 10

echo "Configuration complete. Closing mBlock..."
killall mblock

# Final message
echo "Installation completed successfully. You can now launch mBlock normally."