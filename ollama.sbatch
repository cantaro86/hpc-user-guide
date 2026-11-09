#!/bin/bash
#SBATCH --job-name=ollama
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --gpus-per-node=1
#SBATCH --time=08:30:00
#SBATCH --output=ollama-%j.out
#SBATCH --error=ollama-%j.err

set -euo pipefail

module load ollama

JOBID="${SLURM_JOB_ID:-manual}"
# Port derived from the job ID so jobs sharing a node (or users sharing the
# login node for tunnels) don't collide. Override with PORT=... if needed.
PORT="${PORT:-$((20000 + ${SLURM_JOB_ID:-$$} % 20000))}"
MODEL_NAME="${MODEL_NAME:-qwen3-coder:30b}"
NODE="$(hostname -s)"
BASE_URL="http://127.0.0.1:${PORT}"
LOG="ollama-${JOBID}.log"

export OLLAMA_HOST="127.0.0.1:${PORT}"
export OLLAMA_KEEP_ALIVE="-1"

fail() {
    echo "Error: $*" >&2
    if [[ -s "${LOG}" ]]; then
        echo "--- last lines of ${LOG} ---" >&2
        tail -n 20 "${LOG}" >&2
    fi
    exit 1
}

# OLLAMA_MODELS comes from the ollama modulefile
[[ -n "${OLLAMA_MODELS:-}" ]] || fail "OLLAMA_MODELS is not set; check the ollama modulefile"

# ---- Start the server ------------------------------------------------------
ollama serve >"${LOG}" 2>&1 &
OLLAMA_PID=$!
trap 'kill "${OLLAMA_PID}" 2>/dev/null || true' EXIT

READY=false
for ((attempt = 0; attempt < 60; attempt++)); do
    kill -0 "${OLLAMA_PID}" 2>/dev/null \
        || fail "Ollama failed to start (is port ${PORT} already in use?)"
    if curl -fsS "${BASE_URL}/api/version" >/dev/null 2>&1; then
        READY=true
        break
    fi
    sleep 1
done
[[ "${READY}" == true ]] || fail "Ollama did not become ready within 60 seconds"

# ---- Make sure the model is available --------------------------------------
if ! ollama show "${MODEL_NAME}" >/dev/null 2>&1; then
    echo "Model ${MODEL_NAME} not found in ${OLLAMA_MODELS}; pulling it..."
    ollama pull "${MODEL_NAME}" 2>&1 | tail -n 3 \
        || fail "could not pull ${MODEL_NAME} (no internet on ${NODE}, or ${OLLAMA_MODELS} not writable?)"
fi

# ---- Load the model into GPU memory without generating any text ------------
curl -fsS --max-time 900 "${BASE_URL}/api/generate" \
     -d "{\"model\":\"${MODEL_NAME}\",\"keep_alive\":-1}" >/dev/null \
    || fail "failed to load ${MODEL_NAME}"
kill -0 "${OLLAMA_PID}" 2>/dev/null || fail "Ollama stopped while loading ${MODEL_NAME}"

cat <<EOF
Ollama is ready on compute node ${NODE} (port ${PORT}).

Loaded model:
$(ollama ps)

To use Ollama interactively from the login node:

1. In a terminal on the login node, start this SSH tunnel:
   ssh -N -L ${PORT}:127.0.0.1:${PORT} ${NODE}

   Keep this terminal open. No output is expected while the tunnel runs.

2. Open another terminal on the SAME login node and run:
   module load ollama
   export OLLAMA_HOST=127.0.0.1:${PORT}
   ollama list
   ollama run ${MODEL_NAME}

   'ollama list' shows the models available on the compute node.
   'ollama run' opens an interactive prompt; inference runs on the compute node.
   Type /bye to exit the interactive prompt.

The tunnel forwards the login node's port ${PORT} to Ollama on ${NODE}.
Note: Ollama has no authentication. Other users on ${NODE}, or on the login
node while your tunnel is open, could connect to this port.

Closing the prompt or tunnel does not stop the Slurm job.
To stop the job when finished, run:
   scancel ${JOBID}

Alternatively you can run Ollama commands directly on the compute node using:
   sjoin ${JOBID}
   module load ollama
   export OLLAMA_HOST=127.0.0.1:${PORT}
EOF

wait "${OLLAMA_PID}"
