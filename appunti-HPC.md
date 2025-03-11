# Appunti di HPC

## Connessione via SSH

Utilizzare sempre l’indirizzo IP `158.110.146.245` e connettersi usando il comando:

```bash
ssh tuo_username@158.110.146.245
```

Su Windows, per abilitare la connessione ssh senza password:

```bash
ssh-keygen -t rsa
type $env:USERPROFILE\.ssh\id_rsa.pub | ssh tuo_username@158.110.146.245 "cat >> .ssh/authorized_keys"
```

Su linux o Mac si può usare il comando:

```bash
ssh-copy-id tuo_username@158.110.146.245
```

## Utilizzo di SLURM

Utilizzare sempre i comandi SLURM: `salloc` e `srun`:

- `salloc` serve per allocare risorse

- `srun` per lanciare dei jobs

È buona pratica usare prima `salloc` con tutti i parametri per l’allocazione e poi `srun` per lanciare i jobs.

ESEMPIO:

```bash
salloc --nodes=2 --ntasks=4 --time=00:15:00 --gres=gpu:2 --job-name="device_count"
```

Il comando precedente serve a riservare 2 nodi. Sui nodi riservati stiamo richiedendo anche 4 processi paralleli (`ntasks=4`) in totale, ovvero 2 processi per nodo. In ogni nodo richiediamo 2 GPU, quindi 4 in totale. 

Le informazioni per questa allocazione si possono vedere con `squeue`:

```bash
squeue -u $USER
```

Ora proviamo a vedere quante GPU vede pytorch:

```bash
module load pytorch-conda
srun python -c "import torch; print(torch.cuda.device_count())"
```

L’output che otteniamo è:

```
2
2
2
2
```

Questo perché abbiamo 4 processi paralleli e in ogni nodo pytorch vede 2 GPU.

Una volta finito di lavorare, è necessario liberare lo spazio allocato con il comando `scancel` seguito dal `JOBID`.

```bash
scancel $SLURM_JOB_ID
```

## IMPORTANTE: ssh VS srun --pty /bin/bash -i

Una volta allocato un nodo con `salloc`, è possibile connettersi a quest’ultimo via ssh.  

⚠  Utilizzare ssh solo per fini di debug. Non utilizzare applicazioni direttamente sul nodo perché non vengono gestite da slurm. Bisogna sempre usare `srun`.

Se volete lavorare sul nodo potete utilizzare:

```bash
salloc -N 1 --time=00:15:00 --gres=gpu:1 --job-name="bash"
srun --pty /bin/bash -i
```

Oppure direttamente:

```bash
salloc -N 1 --time=00:15:00 --gres=gpu:1 --job-name="bash" srun --pty /bin/bash -i
```

Scrivendo tutto in una linea, quando si esce dal nodo (con il comando `exit`) non è necessario usare `scancel`.

## Consigliato:

Il comando `salloc` genera delle variabili ambiente di SLURM che non scompaiono dopo aver fatto `scancel`.

Non è necessario eliminarle, ma potrebbe essere utile in certi casi.

Per farlo è possibile ridefinire `scancel` localmente. Aggiungi il seguente codice alla fine del file `~/.bashrc`:

```bash
scancel() {
    command scancel "$@"
    unset $(env | grep ^SLURM_ | grep -v ^SLURM_CONF= | cut -d= -f1)
}
```

## ANACONDA e PYTORCH

Per utilizzare anaconda è necessario caricare il modulo appropriato:

```bash
module load conda
```

Per vedere gli ambienti virtuali esistenti:

```bash
conda env list
```

Al momento esistono due virtual environment di sistema (`base` e `pytorch-2.5.1`). Non utilizzate `base`. L’ambiente `pytorch-2.5.1` contiene i principali pacchetti necessari per lavorare. Per aggiungere pacchetti a questo ambiente contattate gli amministratori di sistema. 

Altrimenti è possibile creare ambienti locali utilizzando il comando:

```bash
conda create -n environment1 python=3.12
```

È consigliato utilizzare gli ambienti di sistema per evitare occupare troppo spazio (ogni ambiente con pytorch occupa diversi GB).

### Modulo di Pytorch

In alternativa, è possibile usare il seguente modulo:

```bash
module load pytorch-conda
```

Questo modulo utilizza lo stesso ambiente virtuale `pytorch-2.5.1` di anaconda. 

Usando il modulo, non è necessario attivare l’ambiente virtuale.

### ESEMPIO 1 (conda environment):

```bash
salloc -N 1 --time=00:15:00 --gres=gpu:1 --job-name="torch_test" srun --pty /bin/bash -i
module load conda
conda activate pytorch-2.5.1
python
>>> import torch
>>> torch.cuda.device_count()          # output 1
>>> exit()
```

### ESEMPIO 2 (modulo):

```bash
salloc -N 1 --time=00:15:00 --gres=gpu:3 --job-name="torch_test" srun --pty /bin/bash -i
module load pytorch-conda
python
>>> import torch
>>> torch.cuda.device_count()          # output 3
>>> exit()
```


## JUPYTER

Il pacchetto di jupyter è installato nell’ambiente conda `pytorch-2.5.1`.

Crea un file di testo e chiamalo `jupyter.sbatch`. Incolla al suo interno lo script in fondo al paragrafo.

Lancia lo script e apri il log file generato.

```bash
sbatch jupyter.sbatch
less jupyter-notebook.log
```

Nel log file c’è il comando ssh che dovrai lanciare sulla tua macchina locale e l’URL da inserire nel browser.

Apri un terminale sulla tua macchina locale e mantienilo aperto finché usi jupyter. Il comando da lanciare sarà simile a  

```bash
ssh -N -f -L 8892:<compute_node>:8892 <tuo_username>@158.110.146.245
```

L’URL da inserire nel browser sarà simile a:

```
http://127.0.0.1:8892/lab?token=0a61901842c346fb6fa059a74ae4a0dd86f88d6217e22780
```

### Script Jupyter

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
