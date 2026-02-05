#!/usr/bin/env sh
set -e

# 1. 基础环境与用户初始化
if ! id -u "$SSH_USER" >/dev/null 2>&1; then
    # Zeabur 挂载后目录已存在，使用 || true 确保 useradd 不因目录存在而报错退出
    useradd -m -s /bin/bash "$SSH_USER" || true
fi

# 【关键修复】不管挂载卷是谁的，一律强制夺取所有权
# 这一步是解决 Zeabur 下无法创建 /home/zv/boot 的核心
echo "正在修正 /home/$SSH_USER 的权限归属..."
chown -R "$SSH_USER":"$SSH_USER" /home/"$SSH_USER"

# 同步密码（使用 SSH_PWD 环境变量）
echo "root:$SSH_PWD" | chpasswd
echo "$SSH_USER:$SSH_PWD" | chpasswd
echo "$SSH_USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/init-users

# 2. 注入全局快捷命令 sctl
ln -sf /usr/bin/supervisorctl /usr/local/bin/sctl

# 3. 持久化初始化逻辑 (强力路径方案)
BOOT_DIR="/home/$SSH_USER/boot"
BOOT_CONF="$BOOT_DIR/supervisord.conf"
TEMPLATE="/usr/local/etc/supervisord.conf.template"

# 强制创建目录，不再依赖逻辑判断
mkdir -p "$BOOT_DIR"

# 只要持久化文件不存在，就执行初始化拷贝
if [ ! -f "$BOOT_CONF" ]; then
    if [ -f "$TEMPLATE" ]; then
        echo "📦 存储卷为空，正在从模板初始化配置..."
        cp "$TEMPLATE" "$BOOT_CONF"
        # 再次确保新文件的所有权
        chown "$SSH_USER":"$SSH_USER" "$BOOT_CONF"
    else
        echo "❌ 警告：未找到模板文件 $TEMPLATE"
    fi
fi

# 4. 确定最终使用的配置文件路径
# 强制锁定：优先使用持久化路径，不再回退到系统的 /etc/ 默认配置
if [ -f "$BOOT_CONF" ]; then
    FINAL_CONF="$BOOT_CONF"
    echo "✅ 成功锁定持久化配置: $FINAL_CONF"
else
    FINAL_CONF="/etc/supervisor/supervisord.conf"
    echo "⚠️ 警告：持久化配置失效，回退至系统默认"
fi

# 5. 清理残留，防止重启自杀 (Zeabur 重启常有此问题)
rm -f /var/run/supervisord.pid /var/run/supervisor.sock /tmp/supervisor.sock

# 6. 动态 Cloudflare 探测
if [ -z "$CF_TOKEN" ] && [ -f "$FINAL_CONF" ]; then
    echo "☁️ 未设置 CF_TOKEN，屏蔽 cloudflare 进程..."
    sed -i '/\[program:cloudflare\]/s/^/;/' "$FINAL_CONF"
    sed -i '/command=cloudflared/s/^/;/' "$FINAL_CONF"
fi

# 7. 启动分流
if [ -n "$SSH_CMD" ]; then
    # 如果定义了 SSH_CMD (环境变量里你改名为 SSH_CMD 了)，则直接执行
    echo "🚀 执行自定义启动命令: $SSH_CMD"
    exec /bin/sh -c "$SSH_CMD"
else
    echo "🛠️ 启动 Supervisord 守护进程..."
    # 强制不使用默认参数，只读我们确认后的 FINAL_CONF
    exec /usr/bin/supervisord -n -c "$FINAL_CONF"
fi
