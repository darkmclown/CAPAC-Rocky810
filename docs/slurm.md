# CAPAC Slurm Cluster Cheat Sheet

## Cluster Layout

| Role | Hostname | IP |
|---|---|---|
| Master + Compute | cae-01 | 192.168.2.131 |
| Compute | cae-03 | 192.168.2.133 |

Partition:

```bash
cfd
```

Shared paths:

```bash
/opt/apps
/opt/modulefiles
/home/data
/home/data/scratch
```

Default users/groups:

```bash
cadfem  # job user
slurm   # Slurm service user
hpc     # shared job-access group
```

---

## 1. Service Commands

### Master service status

```bash
systemctl status munge mariadb slurmdbd slurmctld slurmd --no-pager -l
```

### Compute service status

```bash
systemctl status munge slurmd --no-pager -l
```

### Restart all master services

```bash
sudo systemctl restart munge mariadb slurmdbd slurmctld slurmd
```

### Restart compute services

```bash
sudo systemctl restart munge slurmd
```

### Enable services after reboot

Master:

```bash
sudo systemctl enable munge mariadb slurmdbd slurmctld slurmd slurm-recover
```

Compute:

```bash
sudo systemctl enable munge slurmd slurm-recover
```

---

## 2. Munge Health

```bash
munge -n | unmunge
```

Expected:

```text
STATUS: Success
```

Restart Munge:

```bash
sudo systemctl restart munge
```

Check Munge logs:

```bash
journalctl -u munge -n 100 --no-pager
```

---

## 3. Slurm Health

```bash
scontrol ping
```

Expected:

```text
Slurmctld(primary) at cae-01 is UP
```

Show nodes:

```bash
sinfo -Nel
```

Show partition:

```bash
sinfo
```

Show node details:

```bash
scontrol show nodes
```

Show config:

```bash
scontrol show config
```

---

## 4. Accounting

Show Slurm accounting clusters:

```bash
sacctmgr show cluster
```

Register cluster if missing:

```bash
sudo sacctmgr -i add cluster capac-hpc
sudo systemctl restart slurmdbd slurmctld
```

Show jobs:

```bash
sacct
```

Show recent jobs:

```bash
sacct --starttime now-1day
```

---

## 5. Job Commands

Submit test jobs:

```bash
sbatch /opt/slurm-tests/hostname-test.sbatch
sbatch /opt/slurm-tests/cpu-test.sbatch
```

View queue:

```bash
squeue
```

View all jobs:

```bash
squeue -a
```

Cancel job:

```bash
scancel <jobid>
```

Show job detail:

```bash
scontrol show job <jobid>
```

View output:

```bash
ls -lh /home/data/scratch
cat /home/data/scratch/capac-hostname-*.out
cat /home/data/scratch/capac-cpu-test-*.out
```

---

## 6. Run Interactive Jobs

Interactive shell on partition:

```bash
srun --partition=cfd --nodes=1 --ntasks=1 --pty bash
```

Run hostname across 2 nodes:

```bash
srun --partition=cfd --nodes=2 --ntasks-per-node=1 hostname
```

Run 40 tasks on one node:

```bash
srun --partition=cfd --nodes=1 --ntasks=40 hostname
```

---

## 7. Environment Modules

Load modules:

```bash
source /etc/profile.d/modules.sh
module use /opt/modulefiles
module avail
```

Load OpenMPI:

```bash
module load openmpi/rocky8
which mpirun
mpirun --version
```

Load Intel MPI if installed:

```bash
module load intel-mpi/oneapi
which mpirun
```

---

## 8. Add New HPC User

Add user:

```bash
sudo capac-add-hpc-user username
```

Example:

```bash
sudo capac-add-hpc-user analyst1
```

User must logout/login once to inherit group membership.

Validate:

```bash
id analyst1
sudo -u analyst1 touch /home/data/scratch/analyst1-test.txt
sudo -u analyst1 sbatch /opt/slurm-tests/cpu-test.sbatch
```

---

## 9. Directory Permissions

Check access:

```bash
id cadfem
id slurm
getent group hpc
```

Check shared directories:

```bash
ls -ld /opt/apps /opt/modulefiles /home/data /home/data/scratch
```

Check Slurm directories:

```bash
ls -ld /var/log/slurm /var/spool/slurmd /var/spool/slurmctld
```

Expected:

```text
cadfem and slurm are members of hpc
/home/data/scratch is writable
```

---

## 10. Reboot Validation

After reboot, run on master:

```bash
munge -n | unmunge && \
systemctl is-active slurmdbd slurmctld slurmd && \
scontrol ping && \
sinfo -Nel
```

Expected:

```text
STATUS: Success
active
active
active
Slurmctld(primary) at cae-01 is UP
cae-01 and cae-03 visible
```

On compute:

```bash
munge -n | unmunge && systemctl is-active slurmd
```

---

## 11. Logs

Munge:

```bash
journalctl -u munge -n 100 --no-pager
```

Slurm controller:

```bash
journalctl -u slurmctld -n 100 --no-pager
tail -100 /var/log/slurm/slurmctld.log
```

Slurm database daemon:

```bash
journalctl -u slurmdbd -n 100 --no-pager
tail -100 /var/log/slurm/slurmdbd.log
```

Slurm compute daemon:

```bash
journalctl -u slurmd -n 100 --no-pager
tail -100 /var/log/slurm/slurmd.log
```

---

## 12. Quick All-in-One Health Check

Master:

```bash
echo "=== Munge ===" && munge -n | unmunge | head && \
echo "=== Services ===" && systemctl is-active munge mariadb slurmdbd slurmctld slurmd && \
echo "=== Ping ===" && scontrol ping && \
echo "=== Nodes ===" && sinfo -Nel && \
echo "=== Queue ===" && squeue
```

Compute:

```bash
echo "=== Munge ===" && munge -n | unmunge | head && \
echo "=== Services ===" && systemctl is-active munge slurmd
```

---

## 13. Git Commit Command

After adding or updating `docs/slurm.md`:

```bash
git add docs/slurm.md && git commit -m "Add Slurm operations cheat sheet" && git push origin main
```
