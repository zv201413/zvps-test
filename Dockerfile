FROM ubuntu:22.04

# 基础环境变量
ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Asia/Shanghai \
    SSH_USER=zv \
    SSH_PWD=105106

# 安装基础包
RUN apt-get update && apt-get install -y \
    openssh-server supervisor curl wget sudo ca-certificates \
    tzdata vim net-tools unzip iputils-ping telnet git iproute2 \
    && rm -rf /var/lib/apt/lists/*

# 安装 cloudflared 和 ttyd
RUN curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb \
    && dpkg -i cloudflared.deb \
    && rm cloudflared.deb \
    && curl -L https://github.com/tsl0922/ttyd/releases/download/1.7.3/ttyd.x86_64 -o /usr/local/bin/ttyd \
    && chmod +x /usr/local/bin/ttyd

# 准备 SSH 环境
RUN mkdir -p /run/sshd && ssh-keygen -A \
    && sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config \
    && sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config

# --- 生成配置模板 ---
RUN mkdir -p /usr/local/etc && \
    { \
        echo "[unix_http_server]"; \
        echo "file=/var/run/supervisor.sock"; \
        echo "chmod=0700"; \
        echo ""; \
        echo "[supervisord]"; \
        echo "nodaemon=true"; \
        echo "user=root"; \
        echo "logfile=/var/log/supervisor/supervisord.log"; \
        echo "pidfile=/var/run/supervisord.pid"; \
        echo ""; \
        echo "[rpcinterface:supervisor]"; \
        echo "supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface"; \
        echo ""; \
        echo "[supervisorctl]"; \
        echo "serverurl=unix:///var/run/supervisor.sock"; \
        echo ""; \
        echo "[program:sshd]"; \
        echo "command=/usr/sbin/sshd -D"; \
        echo "autostart=true"; \
        echo "autorestart=true"; \
        echo ""; \
        echo "[program:ttyd]"; \
        echo "command=/usr/local/bin/ttyd -W bash"; \
        echo "autostart=true"; \
        echo "autorestart=true"; \
    } > /usr/local/etc/supervisord.conf.template

# 核心修正：删除系统默认配置，防止路径混淆
RUN rm -f /etc/supervisor/supervisord.conf

# 处理入口脚本
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# 关键：以 root 身份启动，脚本内会处理权限夺取
USER root

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
