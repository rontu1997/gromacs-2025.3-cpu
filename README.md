# GROMACS 2025.3 CPU + MPI

This image builds the official GROMACS **2025.3** source with **Open MPI**, OpenMP,
and single-precision FFTW. It provides `gmx_mpi`, with CPU execution and external
MPI enabled (`GMX_MPI=ON`, `GMX_THREAD_MPI=OFF`, `GMX_GPU=OFF`).

## Build

Run from this folder with Docker Desktop using Linux containers:

```powershell
docker build --progress=plain -t gromacs:2025.3-cpu-mpi .
```

The multi-stage build keeps compilers and source files out of the final image.
The source archive is verified with a pinned SHA-256 checksum. Compilation uses
four jobs by default to limit memory use. To change that:

```powershell
docker build --build-arg BUILD_JOBS=8 -t gromacs:2025.3-cpu-mpi .
```

`GMX_SIMD=Auto` selects instructions for the build host. If moving the image to
older x86-64 CPUs, build a separate portable image with
`--build-arg GMX_SIMD=SSE2`. To explicitly target AVX2 CPUs, use
`--build-arg GMX_SIMD=AVX2_256`.

## Run a simulation from PowerShell

Place your input TPR in a working folder and run this command from that folder:

```powershell
docker run --rm --init --shm-size=1g --mount "type=bind,source=$($PWD.Path),target=/work" gromacs:2025.3-cpu-mpi mpirun -np 4 gmx_mpi mdrun -s topol.tpr -deffnm md -ntomp 1
```

Replace `4` with the desired number of MPI processes, and `topol.tpr` with your
input filename. `-np` takes a positive integer; `*` is a placeholder, not a valid
process count. Output files are written to the mounted folder.

For an interactive shell in the same folder:

```powershell
docker run --rm -it --init --shm-size=1g --mount "type=bind,source=$($PWD.Path),target=/work" gromacs:2025.3-cpu-mpi bash
```

Inside the container:

```bash
mpirun -np 4 gmx_mpi mdrun -s topol.tpr -deffnm md -ntomp 1
```

Use `-np` to select MPI ranks and `-ntomp` for OpenMP threads per rank. For
example, four ranks with two threads each use eight CPU threads. For that layout,
add `--bind-to none` to `mpirun` and set `-ntomp 2` (or choose an explicit Open MPI
binding policy). Keep the total within Docker Desktop's allocated CPU resources.
Do not use `-ntmpi` or `-nt` with this external MPI build.

The image runs as the non-root `gromacs` user (UID 10001), so plain `mpirun` works
without root-specific options. On Linux, use `--user "$(id -u):$(id -g)"` when
mounting a folder owned by your host user. MPI ranks in these examples run inside
one container; running across multiple hosts requires additional networking and
MPI launch configuration.

## Verify

```powershell
docker run --rm gromacs:2025.3-cpu-mpi gmx_mpi --version
docker run --rm --init --shm-size=1g gromacs:2025.3-cpu-mpi gromacs-mpi-smoke-test
```

The smoke test generates a small periodic water system, prepares a TPR, and runs
20 molecular dynamics steps with two MPI ranks. It verifies the version, external
MPI support, rank count, and resulting coordinate, energy, and checkpoint files.
It is a functional check; the full upstream regression suite is not part of this
image build.

Build and run options follow the
[GROMACS 2025.3 installation guide](https://manual.gromacs.org/documentation/2025.3/install-guide/index.html)
and the [GROMACS performance guide](https://manual.gromacs.org/documentation/2025.3/user-guide/mdrun-performance.html).

## PSC tool descriptor

`gromacs-tool.yaml` follows the supplied ASE tool descriptor structure, with a
Bash code environment and the MPI image. Its command starts with `/bin/bash`,
so it works with a runner that launches commands directly. The worker executes
scripts in `/work`, records stdout and stderr in `/work/logs.out`, and preserves
the script's exit status. Configure Discovery's `outputMounts` as `["/work"]` to
capture results directly. Input and output mounts are supplied by PSC.

`tests/discovery-startup-test.sh` checks the runtime and output directory.
`tests/build-tip4p-box.sh` creates a four-site TIP4P water box and updates its
topology's molecule count. Its defaults are a 4 nm box and 1000 waters, matching
the local test system; this has a lower density than liquid water. Pass `4 0` to
fill a 4 nm box without a molecule-count cap.

The public descriptor leaves the ACR image reference blank. Before using it in
PSC, set the private registry login server and publish the local MPI image from
an authenticated Docker session:

```powershell
$registryLoginServer = ''
$publishedImage = "${registryLoginServer}/gromacs:2025.3-cpu-mpi"
docker tag gromacs:2025.3-cpu-mpi $publishedImage
docker push $publishedImage
```
