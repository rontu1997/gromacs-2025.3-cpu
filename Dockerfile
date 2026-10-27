# syntax=docker/dockerfile:1
FROM ubuntu:24.04 AS builder

ARG DEBIAN_FRONTEND=noninteractive
ARG BUILD_JOBS=4
ARG GMX_SIMD=Auto

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential ca-certificates cmake curl \
        libfftw3-dev libopenmpi-dev ninja-build openmpi-bin \
    && rm -rf /var/lib/apt/lists/*

# Pin both the requested release and the checksum of its official source archive.
RUN curl --fail --location --retry 3 \
        https://ftp.gromacs.org/gromacs/gromacs-2025.3.tar.gz \
        --output /tmp/gromacs.tar.gz \
    && echo '8bdfca0268f3f10a7ca3c06e59b62f73ea02420c67211c0ff3912f32d7833c65  /tmp/gromacs.tar.gz' | sha256sum --check - \
    && mkdir -p /src/gromacs \
    && tar -xzf /tmp/gromacs.tar.gz -C /src/gromacs --strip-components=1 \
    && rm /tmp/gromacs.tar.gz

RUN cmake -S /src/gromacs -B /src/build -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/opt/gromacs \
        -DCMAKE_INSTALL_LIBDIR=lib \
        -DGMX_MPI=ON \
        -DGMX_THREAD_MPI=OFF \
        -DGMX_OPENMP=ON \
        -DGMX_GPU=OFF \
        -DGMX_SIMD="${GMX_SIMD}" \
        -DGMX_FFT_LIBRARY=fftw3 \
        -DGMX_BUILD_OWN_FFTW=OFF \
        -DGMXAPI=OFF \
        -DGMX_INSTALL_NBLIB_API=OFF \
        -DBUILD_TESTING=OFF \
        -DREGRESSIONTEST_DOWNLOAD=OFF \
    && cmake --build /src/build --parallel "${BUILD_JOBS}" \
    && cmake --install /src/build

FROM ubuntu:24.04 AS runtime

ARG DEBIAN_FRONTEND=noninteractive
LABEL org.opencontainers.image.title="GROMACS 2025.3 CPU with Open MPI" \
      org.opencontainers.image.version="2025.3" \
      org.opencontainers.image.description="CPU-only GROMACS with external MPI and OpenMP; run mpirun -np N gmx_mpi mdrun"

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates libfftw3-single3 libgomp1 openmpi-bin \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --uid 10001 --shell /bin/bash gromacs \
    && mkdir -p /work \
    && chown gromacs:gromacs /work

COPY --from=builder /opt/gromacs /opt/gromacs
COPY --chmod=755 tests/mpi-smoke-test.sh /usr/local/bin/gromacs-mpi-smoke-test

RUN echo '/opt/gromacs/lib' > /etc/ld.so.conf.d/gromacs.conf \
    && ldconfig

ENV PATH="/opt/gromacs/bin:${PATH}"

USER gromacs
WORKDIR /work

# Leave the command replaceable so docker run IMAGE mpirun ... works directly.
CMD ["gmx_mpi", "--version"]
