import os
import socket
import subprocess
import time
import platform


LOCAL_PORT = 11438
REMOTE_PORT = 11439

def is_port_open(port: int) -> bool:
    """Check if a local TCP port is already open."""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        return s.connect_ex(("127.0.0.1", port)) == 0


def detect_current_node() -> str:
    """
    Detect whether we are on the login node, dgx01, or dgx02.
    Uses hostname and SLURM environment variables if available.
    """
    node = os.getenv("SLURM_NODELIST") or platform.node()
    node = node.strip().lower()
    if "dgx01" in node:
        return "dgx01"
    elif "dgx02" in node:
        return "dgx02"
    else:
        return "login"


def get_active_slurm_node() -> str | None:
    """
    Determine which DGX node is running the user's active job.
    Uses SLURM environment variables or queries squeue/scontrol.
    """
    # First try from environment if running within a SLURM job
    node = os.getenv("SLURM_NODELIST")
    if node:
        node = node.strip().split(",")[0]
        return node

    user = os.getenv("USER")
    if not user:
        return None

    try:
        # Check active jobs
        result = subprocess.run(
            ["squeue", "-u", user, "-h", "-o", "%N"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        nodes = [n.strip() for n in result.stdout.splitlines() if n.strip()]
        if nodes:
            # Return first DGX node found
            for n in nodes:
                if "dgx" in n.lower():
                    return n.split(",")[0]
        return None
    except Exception:
        return None


def open_tunnel(target_host: str, local_port: int, remote_port: int):
    """Open SSH tunnel if not already open."""
    if is_port_open(local_port):
        print(f"[INFO] SSH tunnel already active on port {local_port}.")
        return

    print(
        f"[INFO] Starting SSH tunnel → {target_host}:{remote_port} → localhost:{local_port}"
    )
    subprocess.Popen(
        [
            "ssh",
            "-N",  # no remote shell
            "-f",  # background
            "-L",
            f"{local_port}:localhost:{remote_port}",
            target_host,
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    time.sleep(1)  # give SSH time to establish

    if is_port_open(local_port):
        print("[INFO] Tunnel established successfully.")
    else:
        raise RuntimeError("Failed to establish SSH tunnel.")


def ensure_tunnel_active():

    current_node = detect_current_node()
    print(f"[INFO] Detected current node: {current_node}")

    if current_node in {"dgx01", "dgx02"}:
        print("[INFO] You are already on a compute node — no tunnel needed.")
        return

    # Find which DGX node has your active SLURM job
    target = get_active_slurm_node()
    if not target:
        raise RuntimeError("No active DGX node found via SLURM. Are you running a job?")

    print(f"[INFO] Found active DGX node: {target}")
    open_tunnel(target, LOCAL_PORT, REMOTE_PORT)


if __name__ == "__main__":
    ensure_tunnel_active()
