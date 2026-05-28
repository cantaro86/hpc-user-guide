# HPC Notes

## Table of Contents

1. [Cluster Overview and Usage Policy](#cluster-overview-and-usage-policy)
   - [Cluster Topology](#cluster-topology)
   - [Usage Rules](#usage-rules)

2. [Contacts](#contacts)

3. [Connecting via SSH](#connecting-via-ssh)

4. [Using SLURM](#using-slurm)
   - [salloc VS ssh](#salloc-vs-ssh)
   - [Use sjoin to connect to the compute nodes](#use-sjoin-to-connect-to-the-compute-nodes)
   - [QOS (unlock more GPUs)](#qos-unlock-more-gpus)

5. [ANACONDA and PYTORCH](#anaconda-and-pytorch)
   - [PyTorch Module](#pytorch-module)
   - [EXAMPLE 1 (conda environment)](#example-1-conda-environment)
   - [EXAMPLE 2 (module)](#example-2-module)
   - [Activating a Conda Environment in an sbatch Script](#activating-a-conda-environment-in-an-sbatch-script)

6. [JUPYTER](#jupyter)
   - [Jupyter Script](#jupyter-script)
   - [VS-code jupyter extension](#vs-code-jupyter-extension)

7. [OLLAMA Module](#ollama-module)

8. [Other modules for HPC and pytorch](#other-modules-for-hpc-and-pytorch)

9. [Singularity](#singularity)
   - [OLLAMA container](#ollama-container)
   - [OLLAMA sbatch](#ollama-sbatch)
   - [SSH tunnel](#ssh-tunnel)

10. [Tips](#tips)

11. [Debug python program on the compute node with VS Code](#debug-python-program-on-the-compute-node-with-vs-code)

12. [VS-code server](#vs-code-server)

13. [Storage information](#storage-information)
    - [Where do I save my data on /fast_disk?](#where-do-i-save-my-data-on-fast_disk)
    - [AI-storage module](#ai-storage-module) 

14. [Network Topology](#network-topology)
    - [Node IP Address Reference](#node-ip-address-reference)
    - [`/fast_disk` — BeeGFS Storage](#fast_disk--beegfs-storage)
    - [`/clusterdata` — NAS Storage (NFS v3)](#clusterdata--nas-storage-nfs-v3)
    - [Storage Bandwidth Summary](#storage-bandwidth-summary)



## Cluster Overview and Usage Policy

### Cluster Topology
The HPC cluster is composed of:

- Login node (hpchead01): used for SSH access, job submission (SLURM), file management, and lightweight operations.

- 2 DGX compute nodes (dgx01 and dgx02): GPU-enabled nodes dedicated to all computational workloads (e.g., large simulations, machine learning, data analysis).

### Usage Rules:

- The login node must **not** be used for computational workloads e.g., training, large-scale data processing, long-running scripts.

- All CPU/GPU-intensive tasks must be executed on the compute nodes through the SLURM scheduler.

- Jupyter notebooks using significant resources (GPU, large datasets, high memory) must run on compute nodes.

- Connecting via ssh to compute nodes is not allowed. Direct execution on compute nodes outside scheduled jobs **is not permitted**.

- VS-code with the SSH extension takes up over 1GB of memory. Don't use more than one active vs-code window connected to the cluster.

- If you need specific resources, e.g. one full node for 1 day with no interruptions, ask the administrator for a reservation. 

- AI/ML models and large datasets should not be stored in the `/home`. Use `/clusterdata` or `/fast_disk` instead.

- **Resources must be requested appropriately and not left idle.**


Keeping a model loaded on a GPU consumes power even when you’re not doing inference.
If you won’t use the model for many hours (e.g., overnight), please quit your program.

If you have doubts or questions, please contact the administrator.

## Contacts

- Mailing list: hpc@uniudamce.onmicrosoft.com


## Connecting via SSH

Always use the IP address `158.110.146.245` and connect using the command:

```bash
ssh <your_username>@158.110.146.245
```

On Windows, to enable passwordless SSH connection:

```bash
ssh-keygen -t rsa
type $env:USERPROFILE\.ssh\id_rsa.pub | ssh <your_username>@158.110.146.245 "cat >> .ssh/authorized_keys"
```

On Linux or Mac, you can use the command:

```bash
ssh-copy-id <your_username>@158.110.146.245
```

In the `~/.ssh/config` file, add:

```
Host dgx-login
  HostName 158.110.146.245
  User <your_username>
  IdentityFile ~/.ssh/id_rsa
```

## Using SLURM

In order to use SLURM you need to load the module:

```bash
module load slurm
```

It is recommended to add this line to the `~/.bashrc` file.   

Always use the SLURM commands: `salloc` and `srun`:

- `salloc` is used to allocate resources.
- `srun` is used to launch jobs.

It is good practice to first use `salloc` with all the parameters for allocation and then `srun` to launch the jobs.

EXAMPLE:

```bash
salloc --nodes=2 --ntasks=4 --time=00:15:00 --gres=gpu:1 --job-name="device_count"
```

The previous command reserves 2 nodes. On the reserved nodes, we are also requesting 4 parallel processes (`ntasks=4`) in total, i.e., 2 processes per node. In each node, we request 1 GPUs, so 2 in total.

The information for this allocation can be viewed with `squeue`:

```bash
squeue -u $USER
```

To see all the allocated resources use simply

```bash
squeue
```

Now let's see how many GPUs PyTorch sees:

```bash
module load pytorch
srun python -c "import torch; print(torch.cuda.device_count())"
```

The output we get is:

```
1
1
1
1
```

This is because we have 4 parallel processes, and in each node, PyTorch sees 1 GPUs.

Once you have finished working, it may be necessary to free the allocated space.    
If you allocated with `salloc`, you can simply type `exit`. 
If you used a `sbatch` script ([example below](#jupyter-script)), you can kill your allocation with the command `scancel` followed by the `JOBID`.

```bash
scancel $SLURM_JOB_ID
```

## salloc VS ssh

With the command `salloc` you can directly login into the allocated node:    
```bash
salloc
```
Using the command:
```bash
salloc -N 2
```
you allocate two nodes, but the login is only into the first node (in our case to `dgx01`).   
Using `salloc` is better than using `srun --pty /bin/bash` because it allows you to launch repeated `srun` commands within the allocation (mainly for multi-node allocation).

Once a node is allocated with `salloc` or by submitting a `sbatch` script, it is possible to connect to it from another terminal via `ssh`.  

⚠ Do not run applications directly inside a compute node (if you entered the node by ssh) because they are not managed by SLURM.

⚠ It is **strongly** discouraged to connect to the nodes via ssh!

Use **sjoin** instead!


### Use sjoin to connect to the compute nodes

The `sjoin` command lets you open an interactive shell inside one of your currently running SLURM jobs. This is useful for monitoring progress, inspecting output files, running `nvidia-smi`, or attaching a debugger — all without starting a new job allocation.

- You must have at least one job in **running** state (`R`) on the cluster.
- `sjoin` does **not** start a new job. It attaches to an existing one.

If you have a single running job, just call `sjoin` with no arguments.
If you have multiple running jobs, you must specify the job ID:


**Examples**

```bash
# Single running job — attaches automatically
sjoin

# Multiple running jobs — specify which one to join
sjoin 184630
```

`sjoin` runs the following command under the hood:

```bash
srun --jobid=<id> --overlap --pty --gpus=<num_gpus> --nodelist=<node_name> bash
```

If your job spans multiple nodes, sjoin requires a node name, for example 
```bash
sjoin 185888 dgx02, 
```
to open a shell on the selected allocated node.



## QOS (unlock more GPUs)

In the cluster, we use **Quality of Service (QOS)** to allow users to access resources related to their project.    
You can see the list of qos with the command:

```bash
sacctmgr show qos
```

In order to see which qos you can use, run:

```bash
sacctmgr show assoc where user=$USER
```

By default, each user can access *normal* QOS, which allows them to request up to 2 GPUs.   
The *mira* QOS is reserved for people working the MIRA project, has a limit of 4 GPUs.

Let's see an example:

If you request for instance 3 GPUs with `salloc --gpus=3`. The request will be denied.    
Only if your account belongs to the *mira* project, you can add the option `--qos=mira` and request more GPUs: 

```bash
salloc --qos=mira --gpus=3
```

If you are using a sbatch script, just add the following line at the beginning of the script:

```bash
#SBATCH --qos=mira
```

The qos *longrun* has no restrictions on the number of GPUs.    
But it has low priority, and jobs with higher priority can surpass low-priority jobs by killing and requeuing them.

This is summarized in the following table for the existing QOS:

```bash
sacctmgr show qos format=Name,Priority,Preempt%20,MaxTRESPU%20,MaxJobsPU,MaxWall
```

| Name | Priority | Preempt | MaxTRESPU | MaxJobsPU | MaxWall
| :--- | :--- | :--- | :--- | :--- | :--- |
| normal | 50 | longrun | cpu=100,gres/gpu=2 | 100 | |
| mira | 50 | longrun | cpu=100,gres/gpu=4 | 100 | |
| notimelimit | 0 | | | | | 
| longrun | 1 | | | | 7-00:00:00 |
| urgent | 100 | longrun,normal | cpu=100,gres/gpu=2 | 100 | |

Explanation of the table:
- The QOS *notimelimit* is not available to users. 
- The qos *urgent* let a user allocate at most 2 GPUs, 100 CPUs and 100 jobs. It has the highest priority, and it can replace jobs in the *normal* and *longrun* qos. **Please, use it only if you really need it.**
- *mira* now lets you allocate up to 4 GPUs.
- *longrun* is the qos for long running jobs, up to 7 days.

What happens when a job is preempted?
Initially there is a 5 minute waiting time. After that, the job is stopped, reset to PENDING, and restarts from scratch.

Do you need many GPUs with no interruption? Please, ask the administrator for a reservation. 

-----------------------------


## ANACONDA and PYTORCH

To use Anaconda, you need to load the appropriate module:

```bash
module load conda
```

To see the existing virtual environments, use:

```bash
conda env list
```

Currently, there are several system virtual environments (`base`, `pytorch-2.5.1`, and `ultralytics`).    
Do **not** use `base`.     
The `pytorch-2.5.1` environment contains the main packages needed to work with Python 3.12. The `ultralytics` environment uses Python 3.11. To add packages to an environment, contact the system administrators.

Alternatively, you can create local environments using the command:

```bash
conda create -n environment1 python=3.12
```

It is recommended to use the system environments to avoid taking up too much space (each environment with PyTorch occupies several GB).

You can remove a local conda environment with: 

```bash
conda remove -n environment1 --all
```


### PyTorch Module

Alternatively, you can use modules:

```bash
module load pytorch-conda
```

This module uses the same `pytorch-2.5.1` virtual environment as Anaconda.      
Modules based on Anaconda virtual environments follow a naming convention of the type `<environment_name>-conda`.

This means that at the moment there are the following modules:    
`pytorch-conda`, `ultralytics-conda`.      

You can list all the available modules with

```
module avail
```
and the module you already loaded with
```
module list
```
If you want to unload all the modules, you can run a `module purge`.

When using the module, it is NOT necessary to activate the virtual environment with    
`conda activate <environment_name>`.

### EXAMPLE 1 (conda environment):

```bash
salloc -N 1 --time=00:15:00 --gres=gpu:1 --job-name="torch_test"
module load conda
conda activate pytorch-2.5.1
python
>>> import torch
>>> torch.cuda.device_count()          # output 1
>>> exit()
```

### EXAMPLE 2 (module):

```bash
salloc -N 1 --time=00:15:00 --qos=mira --gres=gpu:3 --job-name="torch_test"
module load pytorch-conda
python
>>> import torch
>>> torch.cuda.device_count()          # output 3
>>> exit()
```

### Activating a Conda Environment in an sbatch Script

Within an `sbatch` script, it is easier to activate a Conda environment by loading the corresponding module, e.g., with `module load pytorch-conda`.

If you want to load an environment for which the associated module does not exist, you need to do this:

```
module load conda
eval "$(conda shell.bash hook)"
conda activate <local_environment>
```

The command with `eval` is used to initialize Conda in the bash shell and be able to activate the environments.

## JUPYTER

The Jupyter package is installed in the `pytorch-2.5.1` Conda environment.

Create a text file and name it `jupyter.sbatch`. Paste the script at the bottom of the paragraph inside it.

Launch the script and open the generated log file.

```bash
sbatch jupyter.sbatch
less jupyter-notebook.log
```

In the log file, there is the SSH command that you will have to launch on your local machine and the URL to enter in the browser.

Open a terminal on your local machine and keep it open while you use Jupyter. The command to launch will be similar to

```bash
ssh -N -f -L 8892:<compute_node>:8892 <your_username>@158.110.146.245
```

The URL to enter in the browser will be similar to:

```
http://127.0.0.1:8892/lab?token=0a61901842c346fb6fa059a74ae4a0dd86f88d6217e22780
```

### Jupyter Script

```bash
#!/bin/bash

#SBATCH --job-name=jupyter-notebook
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=0
#SBATCH --time=00:15:00
#SBATCH --gres=gpu:1
#SBATCH --output=%x.log
#SBATCH --error=%x.log

module load pytorch-conda

node=$(hostname -s)
user=$(whoami)
cluster="158.110.146.245"
port=8892

# print tunneling instructions jupyter-log
echo -e "
Command to create ssh tunnel:
ssh -N -f -L ${port}:${node}:${port} ${user}@${cluster}
Use a Browser on your local machine and paste the address in the output below:
"

# Run Jupyter
jupyter-lab --no-browser --port=${port} --ip=${node}
```

## VS-code jupyter extension

In the sbatch script [jupyter_vscode.sbatch](./jupyter_vscode.sbatch) I propose an upgraded version of the previous script.

The differences are:
- You can activate any personal conda environment
- You can define a jupyter notebook **token**, instead of using the token automatically generated.
- You run the SSH tunnel command from the terminal in VS-code on the login node.

Be careful that if many users use the same script, there may be conflicts with the `port` and `token`. So please modify the current values.

### Instructions

**STEP 1**: run the script

```bash
sbatch jupyter_vscode.sbatch
```

**STEP 2**: Create SSH tunnel from the login node terminal (VS Code terminal).   
For example, if the JupyterLab started on node dgx02, with port=45892 and token="example-vscode"
```bash
user@hpchead01:~$ ssh -N -f -L 45892:dgx02:45892 localhost
```
The correct ssh command can be found in the file `jupyter_vscode.log`.


**STEP 3**: In VS Code top-right:
  1. Select Kernel → Existing Jupyter Server
  2. Paste this URL:
     http://localhost:45892/lab?token=example-vscode

VS-code automatically saves the URL for the next use.

---------------------------

## OLLAMA Module

For using ollama you can load the relevant module as follows:

```bash
module load ollama
```

In this way, you can use the ollama binary inside a slurm allocation.     
For example this is a typical workflow:

```bash
salloc --job-name="ollama" --nodes=1 --ntasks-per-node=1 --cpus-per-task=1 --gpus-per-node=1 --time=00:30:00
module load ollama
export OLLAMA_HOST="http://localhost:11432"
ollama serve &
ollama list
```

Using the `&` we are saying `ollama serve` to run in the background.

By default the PORT used by OLLAMA is 11434. However, if many users run ollama at the same time you need to use a different port. Here we use 11432 as the ollama port.

The models are saved in this path:
```bash
echo $OLLAMA_MODELS 
```


## Other modules for HPC and pytorch

### hpc-tools

If you need to use libraries for HPC software development, mainly in C++ and Python, load the following module:

```bash
module load hpc-tools
```

It contains the latest versions of the main HPC tools:

- gcc-14, cmake-3.31.6, openmpi-5.0.7, openmp, ninja, Eigen3, Boost
- Cuda-12.8
- HWLOC, PMIx, Libevent, and UCX.
- python-12.9

With these libraries, it is possible to write multi-node and multi-GPU code, making GPUs communicate between different nodes.

### pytorch 2.7.0

With a simple
```bash
module load pytorch
```
we can load pytorch 2.7.0. This module depends on *hpc-tools*, so it uses CUDA 12.8 and python 3.12.
This module is not conda based. It does not create a virtual environment, but simply adds pytorch to the PYTHONPATH. 


### HPC CUDA libraries

For the HPC libraries of CUDA (NVIDIA HPC SDK), use the module:

```bash
module load nvhpc
```


## Singularity

If you need to run a container you can do it with Singularity.     
Singularity let's you run Docker and Singularity containers.  


### Interactive approach

Here I show a simple example with a pytorch container:

```bash
module load slurm
module load singularity

singularity pull pytorch_2.7.0-cuda12.8.sif docker://pytorch/pytorch:2.7.0-cuda12.8-cudnn9-runtime

salloc --nodes=1 --ntasks=1 --gpus-per-node=2 --time=00:05:00
singularity shell --nv pytorch_2.7.0-cuda12.8.sif

Singularity> python
>>> import torch 
>>> print(torch.cuda.device_count())
2
>>> exit()
Singularity> exit
exit
```

First we load the slurm and singularity modules.
Then we pull the pytorch docker image from the [docker hub](https://hub.docker.com/r/pytorch/pytorch/tags).
The docker image is converted into a SIF file (singularity image format), and is saved in your current directory.     
Now we can allocate GPUs with salloc, and run the *singularity shell*.  
Inside the container, we can run python, import pytorch and verify the number of reserved GPUs.


### Sbatch file

If we need to run a sbatch process, we can create the script `run_pytorch_test.sbatch`:  

```bash
#!/bin/bash
#SBATCH --job-name=pytorch_test
#SBATCH --nodes=1
#SBATCH --gres=gpu:2
#SBATCH --time=00:05:00
#SBATCH --output=pytorch_test.log


module load singularity

IMAGE="pytorch_2.7.0-cuda12.8.sif"

srun singularity exec --nv $IMAGE python ../cuda_checker.py
```

where the command `srun`, runs the python script inside the container. The IMAGE must be downloaded with `singularity pull` as done before.       
The file `cuda_checker.py` is

```python
import torch

device_count = torch.cuda.device_count()
print(f"Found {device_count} GPU(s)")
``` 


### OLLAMA container

At the moment, it is possible to run *ollama* within a docker container.    
The container can be downloaded with 

```bash
singularity pull ollama.sif docker://ollama/ollama:0.10.0-rc3
```

but it is already available inside the folder: `/home/ollama`.  To run ollama you can follow these commands:

```bash
# load modules
module load slurm singularity

# allocate resources on DGX
salloc --job-name="ollama" --nodes=1 --ntasks-per-node=1 --cpus-per-task=2 --gpus-per-node=1 --time=00:45:00

# define env variables (change the PORT if it is not available)
export OLLAMA_HOST="http://localhost:11435"
export OLLAMA_DIR="/home/ollama"

# Run ollama server
singularity exec --nv \
  -B ${OLLAMA_DIR}:/home/${USER}/.ollama \
  -B /tmp:/tmp \
  --env OLLAMA_HOST=${OLLAMA_HOST} \
  --env OLLAMA_LOG_FILE="ollama.log" \
  --env NVIDIA_VISIBLE_DEVICES=${CUDA_VISIBLE_DEVICES} \
  ${OLLAMA_DIR}/ollama.sif ollama serve &> ollama.log &

# Run an interactive shell
singularity shell --nv -B ${OLLAMA_DIR}:$HOME/.ollama --env OLLAMA_MODELS=$HOME/.ollama --env OLLAMA_HOST=${OLLAMA_HOST} ${OLLAMA_DIR}/ollama.sif

# check list of models
ollama list
```

1) All output is redirected to the log file `ollama.log`.

2) By default, when running the server, the model folder is set to `OLLAMA_MODELS=/home/${USER}/.ollama/models`.
This can be changed with the option `--env OLLAMA_MODELS=/your_path`

3)  Inside the container `$HOME` is automatically set to `/home/${USER}`. In other systems it could be set to `/root/`  

4)  When debugging, you can add these options to the server command: 
```bash
--env OLLAMA_DEBUG=true
--env OLLAMA_LOG_LEVEL=debug
--env OLLAMA_NUM_GPU_LAYERS=150    #  number of transformer layers the Ollama server will place on the GPU
```

### OLLAMA sbatch

The commands in the section above can be run as a sbatch script. The script is available here: 
[ollama.sbatch](./ollama.sbatch) .

You can run it with 
```bash
sbatch ollama.sbatch
```
And read the output file `ollama.out`. It contains information on how to access the running ollama server by using `srun`.
At the end, it is necessary to kill the allocation manually with an scancel.

### SSH tunnel

If you want to interact with the ollama server from a jupyter notebook on the login node, you need to create an ssh tunnel.
The ollama server runs on a compute node, so a tunnel is mandadory. 
The useful program [tunnel.py](tunnel.py) let's you create a tunnel from inside the jupyter notebook.  
You can simply create a cell with:

```python
from ollama_tunnel import ensure_tunnel_active
ensure_tunnel_active() 
```

Reminder:
1) check that the REMOTE_PORT in [tunnel.py](tunnel.py) corresponds to the ollama server port.
2) If you run the jupyter notebook on the same node as the ollama server, there is no need to create a tunnel, and this program does nothing. 
3) If you run the jupyter on the main node, remember to avoid heavy computations. 

----------------------------------------------------------------------------------------------------------------------------


## Tips

### vscode_clean
If you are using the VS-Code extension *"Remote explorer"*, you may have noticed that sometimes there are problems.
A practical way to fix the problems is to kill the VS-Code processes on the login node.

In *~/.bash_aliases* define:

```bash
alias vscode_show='ps aux | grep $(whoami) | grep vscode | grep -v grep'
alias vscode_clean='kill $(vscode_show | sed "s/ \+/ /g" | cut -d" " -f2) 2>/dev/null'
```

You can run *vscode_clean* to kill the processes.

### ssqueue

```bash
alias ssqueue='squeue -o "%i %u %P %T %b %D %C %m %N"'
```

With this command we can see how many GPUs are being used.

### VScode create venv

If you want to create a virtual environment on top of a module, **do not** use VScode, but use the command line.

For example:
```bash
module load pytorch
python -m venv --prompt the_name_you_like ${PWD}/python-venv
source ${PWD}/python-venv/bin/activate
which python
```

This approach is good to save space. But you need to load the module every time before you activate the environment.
If you do it in reverse order, there may be bugs.



## Debug python program on the compute node with VS Code

Debugging a python program that runs on a compute node is not straightforward.
You need the following things:    
- the `Python debugger` extension installed on VS-code.
- a python environment with the package `debugpy` installed.
- an appropriate `.vscode/launch.json` file inside the project home defined as


```json
{
    "version": "0.2.0",
    "configurations": [
        {
            "name": "Python: Remote Attach",
            "type": "debugpy",
            "request": "attach",
            "connect": {
                "host": "localhost",
                "port": 5678
            },
            "pathMappings": [
                {
                    "localRoot": "${workspaceFolder}",
                    "remoteRoot": "/absolute/path/project" 
                }
            ]
        }
    ]
}
```
Replace the remoteRoot and the port if not available.



Let's see how to debug a program together step by step.         
We can debug the program `cuda_checker.py` defined few sections above.

#### 1) Allocate resources:

```bash
salloc --job-name="debug" --nodes=1 --ntasks-per-node=1 --cpus-per-task=2 --gpus-per-node=2 --time=00:45:00
```

#### 2) Create a python venv on top of the pytorch module:

```bash
module load pytorch
python -m venv --prompt the_name_you_like ${PWD}/python-venv
source ${PWD}/python-venv/bin/activate
```

An alternative would be to create and activate a conda environment. Or to use the system environments: `pytorch-2.5.1` or `ultralytics`.

**If you already have an existing virtual environment, skip this point.**

#### 3) Install `debugpy`:

```bash
pip install debugpy
```
Or

```bash
conda install debugpy
```

**If you have already a virtual env with `debugpy`, skip this part.**


#### 4) Run the program:

```bash
python -m debugpy --listen 0.0.0.0:5678 --wait-for-client cuda_checker.py
```

#### 5) Create the ssh tunnel:

Open a new terminal on the login node and run:

```bash
ssh -N -L 5678:dgx01:5678 dgx01
```

Change dgx01 with dgx02 depending on the compute node in use.    
The port number must be consistent with the number used before.


#### 6) Run the debugger

Set some breakpoints and run the debugger.   
If you need to run multiple times, just repeat points (4) and (6). No need to create the ssh tunnel multiple times.



## VS-code server

Since VS-code shells are non-login shells, there may be problems loading the modules.
This happens because the module environment variables (`env | grep MODULE`) must be loaded by sourcing the file
`/etc/profile.d/modules.sh`, which is not sourced for non-login shells (the file `/etc/profile` is not sourced).

This command can show what kind of shell you are using:

```bash
  [ "$0" = "-bash" ] && echo "Login shell" || echo "Non-login shell"
```

To fix the problem, open `File > Preferences > Settings`, select the tab `Remote` and push the button on top-right to open the file `settings.json`.
Paste the following code:

```json
{
    "terminal.integrated.profiles.linux": {
      "bash": {
        "path": "bash",
        "icon": "terminal-bash",
        "args": ["--login"]
      }
    }
}
```

--------------------------------------------------------------------------------------------------------------------------------------




## Storage information


The cluster provides three main storage areas with different performance and persistence characteristics: 
- `/home`
- `/clusterdata`
- `/fast_disk`

Choosing the correct location is essential for performance and data safety.

***

### `/home` — Personal Storage

- Intended for personal files, scripts, environments, and small datasets
- Suitable for code, configuration files, and lightweight data
- Limited performance (1 GbE) and not designed for heavy I/O workloads

Use `/home` as your working environment, but avoid storing large datasets or running I/O-intensive jobs from this path.

***

### `/clusterdata` — Persistent Storage (NAS)

- Shared NFS storage for **long-term data preservation**
- Backed by NAS; reliable but slower than local or BeeGFS storage
- Accessible from all nodes

Typical usage:

- `/clusterdata/datasets/` — source of truth for raw and curated datasets
- `/clusterdata/models/` — long-term storage for trained models and snapshots
- `/clusterdata/ollama/` — shared model storage for Ollama inference

Use this area for data that must be retained over time. For higher speed, data should be copied to `/fast_disk`.

***

### `/fast_disk` — High-Performance Storage (BeeGFS)

- High-speed parallel filesystem over InfiniBand (RDMA)
- Designed for **active workloads and high I/O throughput**
- Data is **not guaranteed to be persistent** and may be cleaned periodically

Typical usage:

- `/fast_disk/models/` — large model weights for fast loading during training/inference
- `/fast_disk/models/ollama/` — ollama models are stored here
- `/fast_disk/models/huggingface` — huggingface models are stored here   
- `/fast_disk/checkpoints/` — training checkpoints with high write throughput
- `/fast_disk/scratch/` — temporary job data (recommended for SLURM jobs)
- `/fast_disk/datasets/text/` — text datasets (many small files)
- `/fast_disk/datasets/photos/` — image datasets
- `/fast_disk/datasets/videos/` — large video datasets
- `/fast_disk/datasets/numerical/` — numerical datasets

Use `/fast_disk` for all performance-critical operations. Always treat it as **temporary storage** and copy important results back to `/clusterdata`.

***


The following table provides a detailed description of each folder:


| Path | Filesystem | Chunk Size | Targets | Purpose |
|------|------------|-----------|---------|---------|
| `/fast_disk/models/` | BeeGFS RAID0 | 16 MiB | 2 | Stores large pre-trained and fine-tuned ML model weights (e.g. LLM `.safetensors`, `.bin` files). Large chunk size optimizes sequential read throughput during model loading at inference or training startup. |
| `/fast_disk/checkpoints/` | BeeGFS RAID0 | 8 MiB | 2 | Stores training checkpoints periodically saved during distributed GPU training (e.g. SLURM jobs on DGX H100). Striped across both nodes for fast write bursts; chunk size balances throughput and I/O granularity. |
| `/fast_disk/scratch/` | BeeGFS RAID0 | 4 MiB | 2 | Temporary high-speed workspace for active SLURM jobs: staged dataset batches, intermediate tensors, ephemeral preprocessing outputs. Data is transient and safe to delete after job completion. |
| `/fast_disk/datasets/text/` | BeeGFS RAID0 | 512 KiB | 1 | Contains text data, tokenized datasets, and NLP data files (typically KB to a few MB each, e.g. `.jsonl`, `.parquet`, `.txt`). Single target avoids metadata overhead from the high volume of small files. |
| `/fast_disk/datasets/photos/` | BeeGFS RAID0 | 2 MiB | 1 | Contains image datasets used for computer vision or multimodal ML training (typical file size 1–50 MB, e.g. JPEG/PNG). Single target is sufficient at this scale; chunk size aligns well with medium-sized image files. |
| `/fast_disk/datasets/videos/` | BeeGFS RAID0 | 8 MiB | 2 | Contains video datasets for ML training tasks such as action recognition or video captioning (files typically 100 MB–several GB, e.g. MP4/MKV). Striped across both nodes to maximize sequential read bandwidth. |
| `/fast_disk/datasets/numerical/` | BeeGFS RAID0 | 4 MiB | 2 | Contains large numerical datasets for ML training: tabular data (CSV, Parquet), array data (HDF5, NPY/NPZ), and other structured formats. |
| `/clusterdata/models/` | NFS (NAS) | — | — | Long-term cold storage for model weights and snapshots. Slower than `/fast_disk`; suitable for archiving released or infrequently used models. Total NAS capacity: 42 TB. |
| `/clusterdata/datasets/` | NFS (NAS) | — | — | Persistent storage for raw and curated datasets. Serves as the source of truth before data is staged into `/fast_disk/datasets/` for active training runs. |
| `/clusterdata/ollama/` | NFS (NAS) | — | — | Stores models and blobs managed by Ollama (local LLM inference runtime). Shared across all cluster nodes via NFS for serving inference requests without duplicating model files. |


- **num-targets**: specifies how many storage servers (the 2 DGX nodes) a file is striped across for parallel read/write performance; 

- **chunk-size**: sets the block size (e.g., 16MiB) written to each target before moving to the next — large for fast big-file access, small to avoid wasting space on tiny files.


#### scratch vs checkpoint

The folders scratch and checkpoint have two different purposes. Let's see a better description:

| Folder                  | Data                                                  | Lifetime              | Purpose                                   |
| ----------------------- | ----------------------------------------------------- | --------------------- | ----------------------------------------- |
| `/fast_disk/scratch/`     | Temporary tensors, staged batches, ephemeral intermediates | Duration of a job     | Fast I/O buffer during active computation |
| `/fast_disk/checkpoints/` | Model weights saved at epoch N                        | Persistent, long-term | Resume training, rollback, evaluation     |

**Example** on how to use the scratch folder

```
# In your SLURM job script
SCRATCH=/fast_disk/scratch/${USER}/${SLURM_JOB_ID}
mkdir -p $SCRATCH
# ... your training code ...
rm -rf $SCRATCH  # cleanup on exit
```

### Where do I save my data on /fast_disk?

You can create a folder with your username and save your data inside it.
For example you can use these paths:

```bash
mkdir /fast_disk/models/$USER
mkdir /fast_disk/checkpoints/$USER
mkdir /fast_disk/dataset/$USER
mkdir /fast_disk/datasets/videos/$USER
```

The folders of `/fast_disk/datasets/{videos,photos,text,numerical}` are optimized for data of a specific size and format.   
**If you need an I/O optimization for your specific dataset, please contact the administrator.**

--------------------------

### AI-storage module

```bash
module load ai-storage
```

This module only defines the environment variables:
```
HF_HOME:               /fast_disk/models/huggingface
TRANSFORMERS_CACHE:    /fast_disk/models/huggingface
HF_DATASETS_CACHE:     /fast_disk/datasets/huggingface
TORCH_HOME:            /fast_disk/models/torch
```

---------------------------


## Network Topology

The cluster uses three distinct networks with different roles.

### Node IP Address Reference

| Node      | Interface        | IP Address        | Network / Role            |
|-----------|------------------|-------------------|---------------------------|
| dgx01     | eno3      | 10.149.146.53     | Internal LAN / BeeGFS mgmt / NAS |
| dgx01     | bond1            | 10.130.122.53     | /clusterdata NFS (RoCE)   |
| dgx01     | ibp24s0          | 10.0.1.1          | BeeGFS RDMA / NCCL (IB)   |
| dgx01     | ibp64s0          | 10.0.2.1          | BeeGFS RDMA / NCCL (IB)   |
| dgx01     | ibp79s0          | 10.0.3.1          | BeeGFS RDMA / NCCL (IB)   |
| dgx01     | ibp94s0          | 10.0.4.1          | BeeGFS RDMA / NCCL (IB)   |
| dgx01     | ibp154s0         | 10.0.5.1          | BeeGFS RDMA / NCCL (IB)   |
| dgx01     | ibp192s0         | 10.0.6.1          | BeeGFS RDMA / NCCL (IB)   |
| dgx01     | ibp206s0         | 10.0.7.1          | BeeGFS RDMA / NCCL (IB)   |
| dgx01     | ibp220s0         | 10.0.8.1          | BeeGFS RDMA / NCCL (IB)   |
| dgx02     | eno3             | 10.149.146.54     | Internal LAN / NAS        |
| dgx02     | bond1            | 10.130.122.54     | /clusterdata NFS (RoCE)   |
| dgx02     | ibp24s0          | 10.0.1.2          | BeeGFS RDMA / NCCL (IB)   |
| dgx02     | ibp64s0          | 10.0.2.2          | BeeGFS RDMA / NCCL (IB)   |
| dgx02     | ibp79s0          | 10.0.3.2          | BeeGFS RDMA / NCCL (IB)   |
| dgx02     | ibp94s0          | 10.0.4.2          | BeeGFS RDMA / NCCL (IB)   |
| dgx02     | ibp154s0         | 10.0.5.2          | BeeGFS RDMA / NCCL (IB)   |
| dgx02     | ibp192s0         | 10.0.6.2          | BeeGFS RDMA / NCCL (IB)   |
| dgx02     | ibp206s0         | 10.0.7.2          | BeeGFS RDMA / NCCL (IB)   |
| dgx02     | ibp220s0         | 10.0.8.2          | BeeGFS RDMA / NCCL (IB)   |
| hpchead01 | eno1             | 158.110.146.206   | Public internet / SSH / default GW |
| hpchead01 | eno2             | 10.149.146.206    | Internal LAN / BeeGFS / NAS |
| hpchead01 | eno3             | 158.110.146.61    | Secondary public interface |
| hpchead01 | eno4             | 10.130.124.1      | Internal cluster management |
| NAS       | —                | 10.149.146.50     | Synology `/volume1/clusterdata` |

### `/fast_disk` — BeeGFS Storage

| Node       | Interface                     | Technology       | Speed                   |
|------------|-------------------------------|------------------|-------------------------|
| dgx01      | ibp24s0 – ibp220s0 (8 ports)  | InfiniBand NDR   | 400 Gbps/port × 8 ports |
| dgx02      | ibp24s0 – ibp220s0 (8 ports)  | InfiniBand NDR   | 400 Gbps/port × 8 ports |
| hpchead01  | eno2 → 10.149.146.206         | Ethernet 1 GbE   | 1 Gbps                  |

- BeeGFS management daemon runs on **dgx01** at `10.149.146.53` (`sysMgmtdHost`)
- DGX nodes use all 8 IB ports via `connInterfaces.conf` for parallel RDMA throughput
- `hpchead01` accesses BeeGFS via `eno2` (1 GbE)

### `/clusterdata` — NAS Storage (NFS v3)

| Node       | Interface              | Technology                       | Speed     |
|------------|------------------------|----------------------------------|-----------|
| dgx01      | bond1 → 10.130.122.53  | 100 GbE RoCE × 2 (LACP 802.3ad) | 200 Gbps  |
| dgx02      | bond1 → 10.130.122.54  | 100 GbE RoCE × 2 (LACP 802.3ad) | 200 Gbps  |
| hpchead01  | eno2 → 10.149.146.206  | Ethernet 1 GbE                   | 1 Gbps    |

- NAS at `10.149.146.50`, NFS v3 over TCP, `rsize/wsize=131072`
- Actual throughput capped by Synology NAS disk and NIC capacity

### Storage Bandwidth Summary

| Path           | Transport on DGX nodes  | Transport on hpchead01 | Max Bandwidth (DGX) |
|----------------|-------------------------|------------------------|---------------------|
| `/fast_disk`   | InfiniBand NDR (RDMA)   | Ethernet 1 GbE (eno2)  | 400 Gbps × 8 ports  |
| `/clusterdata` | 100 GbE RoCE (bond1)    | Ethernet 1 GbE (eno2)  | 200 Gbps            |
| `/home`        | Ethernet 1 GbE (eno3)   | Ethernet 1 GbE (eno2)  | 1 Gbps              |
| `/cm/shared`   | Ethernet 1 GbE (eno3)   | Ethernet 1 GbE (eno2)  | 1 Gbps              |