#!/bin/sh
# Generate a real water system and run CPU molecular dynamics on two MPI ranks.
set -eu

test_dir=$(mktemp -d /tmp/gromacs-mpi-smoke.XXXXXX)
# Keep results until the ephemeral container exits, including on failure.
cd "$test_dir"

gmx_mpi --version > version.log 2>&1
cat version.log
grep -Eq 'GROMACS version:[[:space:]]+2025\.3([[:space:]]|$)' version.log
grep -Eq 'MPI library:[[:space:]]+MPI' version.log

cat > topol.top <<'EOF'
#include "oplsaa.ff/forcefield.itp"
#include "oplsaa.ff/spc.itp"

[ system ]
MPI smoke test: water

[ molecules ]
EOF

gmx_mpi solvate -cs spc216.gro -box 3 3 3 -o water.gro -p topol.top > solvate.log 2>&1 \
    || { cat solvate.log; exit 1; }

cat > md.mdp <<'EOF'
integrator               = md
dt                       = 0.001
nsteps                   = 20
cutoff-scheme            = Verlet
nstlist                  = 10
coulombtype              = PME
rcoulomb                 = 1.0
vdwtype                  = Cut-off
rvdw                     = 1.0
constraints              = none
tcoupl                   = no
pcoupl                   = no
gen-vel                  = yes
gen-temp                 = 100
gen-seed                 = 12345
nstenergy                = 10
nstlog                   = 10
nstxout                  = 0
nstvout                  = 0
nstfout                  = 0
pbc                      = xyz
EOF

gmx_mpi grompp -f md.mdp -c water.gro -p topol.top -o md.tpr > grompp.log 2>&1 \
    || { cat grompp.log; exit 1; }

# Disabling binding keeps this short functional check independent of CPU affinity.
mpirun --bind-to none -np 2 gmx_mpi mdrun \
    -s md.tpr -deffnm md -ntomp 1 -npme 0 -pin off > mdrun.log 2>&1 \
    || { cat mdrun.log; exit 1; }
cat mdrun.log
grep -Eq 'Using 2 MPI (processes|ranks)' mdrun.log
test -s md.gro
test -s md.edr
test -s md.cpt
echo 'PASS: GROMACS 2025.3 completed 20 MD steps with 2 external MPI ranks.'
