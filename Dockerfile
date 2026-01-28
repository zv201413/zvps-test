FROM ubuntu:22.04

# 1. 禁用交互模式并安装基础依赖
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    openssh-server supervisor curl wget sudo ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# 2. 预装 Cloudflared 和 ttyd
# 安装 Cloudflared
RUN curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb \
    && dpkg -i cloudflared.deb \
    && rm cloudflared.deb

# 安装 ttyd (网页版终端)
RUN curl -L https://github.com/tsl0922/ttyd/releases/download/1.7.3/ttyd.x86_64 -o /usr/local/bin/ttyd \
    && chmod +x /usr/local/bin/ttyd

# 3. 极速修复 SSH 权限与目录
RUN mkdir -p /run/sshd /etc/supervisor/conf.d && \
    sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config && \
    sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/g' /etc/ssh/sshd_config && \
    ssh-keygen -A

# 4. 用户设置
RUN useradd -m -s /bin/bash zv && \
    echo "zv:105106" | chpasswd && \
    echo "root:105106" | chpasswd && \
    echo "zv ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# 5. 生成综合配置文件 (包含 ttyd)
# 注意：ttyd 默认监听 7681 端口，启动后直接进入 bash
RUN printf "[supervisord]\n\
nodaemon=true\n\
user=root\n\
\n\
[program:sshd]\n\
command=/usr/sbin/sshd -D\n\
autorestart=true\n\
\n\
[program:cloudflared]\n\
command=bash -c \"/usr/bin/cloudflared tunnel --no-autoupdate run --token \${CF_TOKEN}\"\n\
autorestart=true\n\
\n\
[program:ttyd]
command=/usr/local/bin/ttyd -W bash
autorestart=true\n" > /etc/supervisord.conf

# 6. 设置工作目录
WORKDIR /home/zv

# 7. 启动脚本 (逻辑优化)
# 只要 CF_TOKEN 填对了，不管有没有挂载卷，都会先跑镜像内的配置确保你能进去
CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisord.conf"]
