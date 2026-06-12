# syntax=docker/dockerfile:1.6

# 当前为从 cuda 128 版本复制来的模板,后续会做适当修改以适配 cuda 118 版本
FROM nvidia/cuda:12.8.1-cudnn-devel-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Shanghai
ENV PIP_NO_CACHE_DIR=1
ENV CONDA_DIR=/opt/conda
ENV PROJECT_DIR=/workspace/object-rel-nav
ENV CONDA_DEFAULT_ENV=object-rel-nav
ENV PATH=${CONDA_DIR}/bin:${PATH}
ENV PYTHONPATH=${PROJECT_DIR}:${PROJECT_DIR}/libs/habitat-lab/habitat-lab
ENV HF_HOME=/cache/huggingface

SHELL ["/bin/bash", "-lc"]

# 配置 ubuntu 镜像源
RUN sed -i 's@http://archive.ubuntu.com/ubuntu/@https://mirrors.aliyun.com/ubuntu/@g' /etc/apt/sources.list && \
    sed -i 's@http://security.ubuntu.com/ubuntu/@https://mirrors.aliyun.com/ubuntu/@g' /etc/apt/sources.list

# 安装系统依赖
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget curl git git-lfs unzip bzip2 ca-certificates bash sudo \
    build-essential ninja-build pkg-config \
    vim tmux less \
    libglib2.0-0 libsm6 libxext6 libxrender1 \
    libgl1 libgomp1 \
    libegl1 libglvnd0 libopengl0 libgles2 libglx0 \
    && rm -rf /var/lib/apt/lists/*

# 安装 miniconda
RUN wget -qO /tmp/miniconda.sh https://mirrors.tuna.tsinghua.edu.cn/anaconda/miniconda/Miniconda3-latest-Linux-x86_64.sh && \
    bash /tmp/miniconda.sh -b -p ${CONDA_DIR} && \
    rm -f /tmp/miniconda.sh && \
    conda clean -afy

RUN cat > /root/.condarc <<'EOF_CONDA'
channels:
  - conda-forge
show_channel_urls: true
channel_priority: strict
default_channels:
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/main
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/r
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/msys2
custom_channels:
  conda-forge: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
  nvidia: https://mirrors.sustech.edu.cn/anaconda-extra/cloud
  aihabitat: https://conda.anaconda.org
EOF_CONDA


# 配置 pip 镜像源
RUN mkdir -p /root/.pip && cat > /root/.pip/pip.conf <<'EOF_PIP'
[global]
index-url = https://mirrors.aliyun.com/pypi/simple/
trusted-host = mirrors.aliyun.com
EOF_PIP

# 创建 mamba 环境
RUN conda create -n mamba python=3.9 mamba -c conda-forge -y && \
    conda clean -afy

# 目标环境安装 conda 包
COPY object-rel-nav.yml /tmp/object-rel-nav.yml
RUN sed -i '/^prefix:/d' /tmp/object-rel-nav.yml && \
    conda run -n mamba mamba env create -f /tmp/object-rel-nav.yml -n object-rel-nav && \
    conda clean -afy

# 目标环境安装 pip 包
RUN --mount=type=bind,from=torch_wheels,source=torch271_cu128_py39,target=/tmp/wheels/torch271_cu128_py39,readonly \
    source "${CONDA_DIR}/etc/profile.d/conda.sh" && \
    conda activate object-rel-nav && \
    python -m pip install --upgrade pip setuptools wheel && \
    python -m pip install \
      --no-index \
      --find-links=/tmp/wheels/torch271_cu128_py39 \
      torch==2.7.1+cu128 \
      torchvision==0.22.1+cu128 \
      torchaudio==2.7.1+cu128 && \
    python -m pip list --format=freeze > /tmp/object-rel-nav-constraints.txt && \
    PIP_EXTRA_PKGS=( \
      kornia \
      open-clip-torch \
      ultralytics \
      warmup-scheduler \
      efficientnet-pytorch \
      vit-pytorch \
      lmdb \
      prettytable \
      diffusers \
    ) && \
    python -m pip install --dry-run -c /tmp/object-rel-nav-constraints.txt "${PIP_EXTRA_PKGS[@]}" && \
    python -m pip install -c /tmp/object-rel-nav-constraints.txt "${PIP_EXTRA_PKGS[@]}" && \
    python -m pip check 

# 目标环境安装 git 项目包
RUN git clone https://gitee.com/xie-ziyang1/habitat-lab.git /tmp/lib/habitat-lab && \
cd /tmp/lib/habitat-lab && \
git checkout v0.2.4

RUN source "${CONDA_DIR}/etc/profile.d/conda.sh" && \
    conda activate object-rel-nav && \
    python -m pip install --dry-run -c /tmp/object-rel-nav-constraints.txt -e /tmp/lib/habitat-lab/habitat-lab && \
    python -m pip install -c /tmp/object-rel-nav-constraints.txt -e /tmp/lib/habitat-lab/habitat-lab && \
    python -m pip check

ENV PATH=${CONDA_DIR}/envs/object-rel-nav/bin:${CONDA_DIR}/bin:${PATH}

RUN mkdir -p "${PROJECT_DIR}" "${HF_HOME}" && \
    chmod 777 "${HF_HOME}"

WORKDIR ${PROJECT_DIR}

CMD ["/bin/bash"]
