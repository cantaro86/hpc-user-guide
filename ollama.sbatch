#!/bin/bash
#SBATCH --job-name=ollama
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=16
#SBATCH --gpus-per-node=1
#SBATCH --time=01:45:00
#SBATCH --output=ollama.out
#SBATCH --error=ollama.err

# -------------------------------
# 1. Load environment
# -------------------------------
module load singularity

# -------------------------------
# 2. Set variables
# -------------------------------

export OLLAMA_DIR="/home/ollama"
export SIF_FILE="${OLLAMA_DIR}/ollama.sif"
export SIF_URI="docker://ollama/ollama:0.10.0-rc3"
export OLLAMA_HOST="http://localhost:11439"



echo "==============================="
echo " SLURM job started on $(hostname)"
echo " Job ID: $SLURM_JOB_ID"
echo "==============================="

# -------------------------------
# 3. Pull container if missing
# -------------------------------
if [ ! -f "$SIF_FILE" ]; then
    echo "[INFO] Ollama container not found in ${OLLAMA_DIR}, pulling from $SIF_URI ..."
    mkdir -p "${OLLAMA_DIR}"
    # Use a temp file to avoid partial downloads if interrupted
    TMP_SIF="${OLLAMA_DIR}/ollama_tmp_$$.sif"
    singularity pull "${TMP_SIF}" "${SIF_URI}" && mv "${TMP_SIF}" "${SIF_FILE}"
    echo "[INFO] Container saved to ${SIF_FILE}"
else
    echo "[INFO] Container ${SIF_FILE} already exists — skipping download."
fi

# -------------------------------
# 4. Start Ollama server
# -------------------------------
echo "Starting Ollama server..."
singularity exec --nv \
  -B ${OLLAMA_DIR}:/home/${USER}/.ollama \
  -B /tmp:/tmp \
  --env OLLAMA_HOST=${OLLAMA_HOST} \
  --env NVIDIA_VISIBLE_DEVICES=${CUDA_VISIBLE_DEVICES} \
  ${SIF_FILE} ollama serve &


SERVER_PID=$!
sleep 4


# -------------------------------
# 5. Display connection info
# -------------------------------

cat <<EOF

==========================================================
✅ Ollama server is running on node: $(hostname)
   Host URL: ${OLLAMA_HOST}

To open an interactive shell in the same job, run this
**from your login node** (NOT inside this job):

    srun --jobid=${SLURM_JOB_ID} --pty bash -c "module load singularity && singularity shell --nv -B ${OLLAMA_DIR}:\$HOME/.ollama --env OLLAMA_MODELS=\$HOME/.ollama --env OLLAMA_HOST=${OLLAMA_HOST} ${SIF_FILE}"

Notes:
- \$HOME inside the container is automatically set to your home directory.
- This ensures that Ollama models are stored in the shared folder: ${OLLAMA_DIR}

When finished, exit the shell with 'exit' and cancel the job:
  scancel ${SLURM_JOB_ID}
==========================================================

EOF


# -------------------------------
# 6. Keep the job alive
# -------------------------------
tail -f /dev/null