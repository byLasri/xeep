#!/bin/bash
set -e

echo "=== Setting up Agent Bridge ==="

# Install wrangler globally
npm install -g wrangler

# Install Python deps for bridge
pip install fastapi uvicorn httpx 2>/dev/null || pip3 install fastapi uvicorn httpx

# Generate a shared secret
SECRET=$(python3 -c "import uuid; print(str(uuid.uuid4()))")

# Write the bridge server to codespace home (NOT in the repo)
cat > /home/codespace/bridge_server.py << 'PYEOF'
import os, json, subprocess, uuid
from fastapi import FastAPI, Request, HTTPException
from fastapi.responses import JSONResponse

STATE_FILE = "/home/codespace/.agent_state.json"

app = FastAPI(title="Agent Bridge")

def load_state():
    try:
        with open(STATE_FILE) as f:
            return json.load(f)
    except:
        return {}

@app.get("/health")
async def health():
    return {"status": "ok", "cwd": os.getcwd()}

@app.get("/state")
async def state(request: Request):
    s = load_state()
    secret = request.headers.get("X-Agent-Secret", "")
    if secret != s.get("shared_secret", ""):
        raise HTTPException(403, "Invalid secret")
    return s

@app.post("/execute")
async def execute(request: Request):
    s = load_state()
    secret = request.headers.get("X-Agent-Secret", "")
    if secret != s.get("shared_secret", ""):
        raise HTTPException(403, "Invalid secret")
    
    body = await request.json()
    cmd = body.get("cmd", "")
    cwd = body.get("cwd", "/workspaces/xeep")
    timeout = body.get("timeout", 120)
    
    if not cmd:
        raise HTTPException(400, "No command provided")
    
    try:
        result = subprocess.run(
            cmd, shell=True, capture_output=True, text=True,
            cwd=cwd, timeout=timeout
        )
        return {
            "stdout": result.stdout[-10000:],
            "stderr": result.stderr[-5000:],
            "returncode": result.returncode
        }
    except subprocess.TimeoutExpired:
        return {"stdout": "", "stderr": "Command timed out", "returncode": -1}
    except Exception as e:
        return {"stdout": "", "stderr": str(e), "returncode": -1}

@app.post("/write_file")
async def write_file(request: Request):
    s = load_state()
    secret = request.headers.get("X-Agent-Secret", "")
    if secret != s.get("shared_secret", ""):
        raise HTTPException(403, "Invalid secret")
    
    body = await request.json()
    path = body.get("path", "")
    content = body.get("content", "")
    
    if not path:
        raise HTTPException(400, "No path provided")
    
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(content)
    return {"status": "ok", "path": path}

@app.get("/read_file")
async def read_file(request: Request, path: str = ""):
    s = load_state()
    secret = request.headers.get("X-Agent-Secret", "")
    if secret != s.get("shared_secret", ""):
        raise HTTPException(403, "Invalid secret")
    
    if not path or not os.path.exists(path):
        raise HTTPException(404, "File not found")
    
    with open(path) as f:
        return {"content": f.read()[:50000]}
PYEOF

# Write the state file with the secret and codespace info
CODESPACE_NAME=$(cat /workspaces/.codespace 2>/dev/null || echo "unknown")
cat > /home/codespace/.agent_state.json << EOF
{
    "shared_secret": "${SECRET}",
    "codespace_name": "${CODESPACE_NAME:-set-later}",
    "bridge_port": 8080,
    "repo": "byLasri/xeep",
    "workdir": "/workspaces/xeep",
    "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

echo "=== Bridge server written to /home/codespace/bridge_server.py ==="
echo "=== State file written to /home/codespace/.agent_state.json ==="
echo "=== Secret: ${SECRET} ==="

# Start the bridge server in background
cd /home/codespace
nohup python3 -m uvicorn bridge_server:app --host 0.0.0.0 --port 8080 > /home/codespace/bridge.log 2>&1 &
echo "=== Bridge server started on port 8080 ==="
echo "=== Setup complete ==="
