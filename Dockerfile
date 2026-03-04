FROM nvidia/cuda:11.8.0-devel-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8

# System deps including X11/OpenGL for Blender EEVEE
RUN apt-get update && apt-get install -y \
    wget git curl unzip software-properties-common \
    xvfb libxi6 libxxf86vm1 libxfixes3 libxrender1 libxrandr2 \
    libxinerama1 libxcursor1 libgl1-mesa-glx libgl1-mesa-dri \
    libglew-dev libsm6 mesa-utils build-essential cmake \
    && rm -rf /var/lib/apt/lists/*

# Python 3.10 via deadsnakes
RUN add-apt-repository ppa:deadsnakes/ppa && apt-get update \
    && apt-get install -y python3.10 python3.10-venv python3.10-dev python3.10-distutils \
    && rm -rf /var/lib/apt/lists/*

# Make python3.10 the default
RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.10 1 \
    && update-alternatives --set python3 /usr/bin/python3.10 \
    && ln -sf /usr/bin/python3.10 /usr/bin/python

# Install pip for 3.10
RUN curl -sS https://bootstrap.pypa.io/get-pip.py | python3.10

# ===== Python packages (VLMaterial exact versions) =====
RUN pip install --no-cache-dir \
    torch==2.4.1 torchvision==0.19.1 --index-url https://download.pytorch.org/whl/cu118
RUN pip install --no-cache-dir \
    transformers==4.45.2 peft==0.13.2 accelerate==1.0.1 \
    numpy scipy Pillow pyyaml tqdm \
    lpips tensorboardX fake-bpy-module-3-3 \
    gdown fastapi uvicorn python-multipart

# Flash attention (exact version from VLMaterial README)
RUN cd /tmp && wget -q https://github.com/Dao-AILab/flash-attention/releases/download/v2.6.3/flash_attn-2.6.3+cu118torch2.4cxx11abiFALSE-cp310-cp310-linux_x86_64.whl \
    && pip install --no-cache-dir flash_attn-2.6.3+cu118torch2.4cxx11abiFALSE-cp310-cp310-linux_x86_64.whl --no-build-isolation \
    && rm -f flash_attn*.whl

# ===== Blender 3.3.1 =====
RUN wget -q https://download.blender.org/release/Blender3.3/blender-3.3.1-linux-x64.tar.xz -O /tmp/blender.tar.xz \
    && tar xf /tmp/blender.tar.xz -C /opt/ \
    && mv /opt/blender-3.3.1-linux-x64 /opt/blender \
    && rm /tmp/blender.tar.xz
ENV BLENDER=/opt/blender/blender

# ===== Blender's bundled Python 3.10 packages =====
# (Blender ships its own Python 3.10 — need packages there too for render.py)
ENV BPYTHON=/opt/blender/3.3/python/bin/python3.10
ENV BINCLUDE=/opt/blender/3.3/python/include/python3.10

# Python headers for C extensions
RUN wget -q https://www.python.org/ftp/python/3.10.2/Python-3.10.2.tgz -O /tmp/py.tgz \
    && tar xf /tmp/py.tgz -C /tmp/ \
    && cp -r /tmp/Python-3.10.2/Include/* ${BINCLUDE}/ \
    && rm -rf /tmp/py.tgz /tmp/Python-3.10.2

RUN ${BPYTHON} -m ensurepip \
    && ${BPYTHON} -m pip install --upgrade pip

# Install ALL infinigen requirements + VLMaterial deps into Blender's Python
COPY infinigen_requirements.txt /tmp/reqs.txt
RUN CFLAGS="-I${BINCLUDE}" ${BPYTHON} -m pip install --no-cache-dir -r /tmp/reqs.txt || true
RUN ${BPYTHON} -m pip install --no-cache-dir Pillow lpips pyyaml tqdm scipy matplotlib || true

# Model downloads at runtime on vast.ai (~5 min, cached after first run)
# Not baked into image to stay under GHA disk limits

WORKDIR /root/VLMaterial
