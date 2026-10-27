#!/bin/bash
# Optional arguments: box edge in nm (default 4), water cap (default 1000).
# A water cap of 0 fills the box without a molecule-count cap.
set -euo pipefail
cd /work

box_nm=${1:-4}
max_waters=${2:-1000}
if ! [[ "$box_nm" =~ ^[0-9]+([.][0-9]+)?$ ]] \
    || ! awk -v edge="$box_nm" 'BEGIN { exit !(edge > 0) }'; then
    echo 'Box edge must be a positive number in nm.' >&2
    exit 2
fi
if ! [[ "$max_waters" =~ ^[0-9]+$ ]]; then
    echo 'Water cap must be a non-negative integer; 0 means no cap.' >&2
    exit 2
fi

solvent=/opt/gromacs/share/gromacs/top/tip4p.gro
test -r "$solvent"

cat > topol.top <<'EOF'
#include "amber99sb.ff/forcefield.itp"
#include "amber99sb.ff/tip4p.itp"

[ system ]
TIP4P water box

[ molecules ]
EOF

solvate_args=(-cs "$solvent" -box "$box_nm" "$box_nm" "$box_nm"
              -o box_tip4p.gro -p topol.top)
if [[ "$max_waters" != 0 ]]; then
    solvate_args+=(-maxsol "$max_waters")
fi
gmx_mpi solvate "${solvate_args[@]}" > solvate.log 2>&1 \
    || { cat solvate.log >&2; exit 1; }

atoms=$(awk 'NR == 2 { print $1; exit }' box_tip4p.gro)
waters=$(awk '$1 == "SOL" { print $2; exit }' topol.top)
if ! [[ "$atoms" =~ ^[0-9]+$ && "$waters" =~ ^[0-9]+$ ]] \
    || (( atoms != 4 * waters )); then
    echo 'TIP4P coordinate site count does not match the topology water count.' >&2
    exit 1
fi
if [[ "$max_waters" != 0 ]] && (( waters != max_waters )); then
    echo "Box holds $waters waters, fewer than the requested cap $max_waters." >&2
    exit 1
fi

{
    printf 'Box: %s x %s x %s nm\n' "$box_nm" "$box_nm" "$box_nm"
    printf 'TIP4P water molecules: %s\nCoordinate sites: %s\n' "$waters" "$atoms"
    grep '^Density' solvate.log || true
} | tee summary.txt
