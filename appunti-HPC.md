# HPC Notes

## Table of Contents

1. [Connecting via SSH](#connecting-via-ssh)

2. [Using SLURM](#using-slurm)
   - [salloc VS ssh](#salloc-vs-ssh)
   - [QOS (unlock more GPUs)](#qos-unlock-more-gpus)

3. [ANACONDA and PYTORCH](#anaconda-and-pytorch)
   - [Example 1: Conda Environment](#example-1-conda-environment)
   - [Example 2: Module](#example-2-module)
   - [Activating a Conda Environment in an sbatch Script](#activating-a-conda-environment-in-an-sbatch-script)

4. [JUPYTER](#jupyter)
   - [Jupyter Script](#jupyter-script)

5. [OLLAMA Module](#ollama-module)

6. [Other modules for HPC and pytorch](#other-modules-for-hpc-and-pytorch)

7. [Singularity](#singularity)
   - [OLLAMA container](#ollama-container)
   - [OLLAMA sbatch](#ollama-sbatch)
   - [SSH tunnel](#ssh-tunnel)

8. [Tips](#tips)

8. [Debugging](#debug-python-program-on-the-compute-node-with-vs-code)

9. [VS-code server](#vs-code-server)


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

With the command `salloc` you connect directly to the allocated node.    
Using the command
```bash
salloc -N 2
```
you allocate two nodes, but the login is into the first node (in our case to `dgx01`).   
Using `salloc` is better than using `srun --pty /bin/bash` because it allows you to launch repeated `srun` commands within the allocation.

Once a node is allocated with `salloc` or by submitting a `sbatch` script, it is possible to connect to it from another terminal via `ssh`.

⚠ Use SSH only for debugging purposes. Do not run applications directly inside a compute node (if you entered the node by ssh) because they are not managed by SLURM. You should always launch jobs inside a slurm allocation.



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
The *mira* QOS on the other hand has no restrictions on the number of GPUs.

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
export OLLAMA_HOST="http://localhost:${SLURM_JOB_ID}"
ollama serve &
ollama list
```

Using the `&` we are saying `ollama serve` to run in the background.

By default the PORT used by OLLAMA is 11434. However, if many users run ollama at the same time you need to use a different port. Here we use the SLURM_JOB_ID as the ollama port.

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
singularity shell --nv pytorch_2.7.0-cuda12.8-cudnn9-runtime.sif

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
The ollama server runs on a compute node, so a tunnel in mandadory. 
The useful program [ollama_tunnel.py](ollama_tunnel.py) let's you create a tunnel from inside the jupyter notebook.  
You can simply create a cell with:

```python
from ollama_tunnel import ensure_tunnel_active
ensure_tunnel_active() 
```

Reminder:
1) check that the REMOTE_PORT in [ollama_tunnel.py](ollama_tunnel.py) corresponds to the ollama server port.
2) If you run the jupyter notebook on the same node as the ollama server, there is no need to create a tunnel, and this program does nothing. 

========================================================================================================

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

