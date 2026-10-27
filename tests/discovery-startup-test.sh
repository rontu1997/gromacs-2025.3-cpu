#!/bin/bash
set -euo pipefail
cd /work
id
pwd
test -w /work
command -v bash
command -v gmx_mpi
command -v mpirun
gmx_mpi --version
mpirun --version
printf 'Discovery runtime startup check passed.\n' > startup-ok.txt
cat startup-ok.txt
