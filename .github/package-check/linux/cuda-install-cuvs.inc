    curl -Ls https://micro.mamba.pm/api/micromamba/linux-64/latest | \
        tar -xj -C /usr/local bin/micromamba
    MAMBA_ROOT_PREFIX=/opt/micromamba /usr/local/bin/micromamba create -y \
        -p /opt/cuvs -c rapidsai -c conda-forge -c nvidia \
        "libcuvs=26.06.*" "cuda-version=13.2"
