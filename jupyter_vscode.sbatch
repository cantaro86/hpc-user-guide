#!/bin/bash

#SBATCH --job-name=jupyter_vscode
#SBATCH --qos=normal

#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --gres=gpu:1
#SBATCH --mem=0
#SBATCH --time=01:00:00

#SBATCH --output=%x.log
#SBATCH --error=%x.log


module load conda
eval "$(conda shell.bash hook)"
conda activate <your_conda_env>

node=$(hostname -s)
port=8881
token="example-vscode"

echo
echo "Jupyter job started on node: ${node}"
echo
echo "From the VS Code terminal already running on dgx-login, create this tunnel:"
echo "ssh -N -f -L ${port}:${node}:${port} localhost"
echo
echo "Then in VS Code use:"
echo "  Select Kernel -> Existing Jupyter Server"
echo "and paste this URL:"
echo "  http://localhost:${port}/lab?token=${token}"
echo

jupyter-lab \
  --no-browser \
  --port="${port}" \
  --ip=0.0.0.0 \
  --ServerApp.allow_remote_access=True \
  --IdentityProvider.token="${token}" \
  --ServerApp.root_dir="${SLURM_SUBMIT_DIR}"
