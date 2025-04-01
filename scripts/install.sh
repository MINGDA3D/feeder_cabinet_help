#!/bin/bash
# 送料柜自动续料系统安装脚本

set -e

# 显示安装信息
echo "==== 送料柜自动续料系统安装脚本 ===="
echo "该脚本将安装送料柜自动续料系统及其依赖项"
echo

# 检查是否以root权限运行
if [ "$EUID" -ne 0 ]; then
  echo "需要root权限才能进行安装"
  echo "请使用 'sudo' 重新运行此脚本"
  exit 1
fi

# 确定脚本所在目录
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="/etc/feeder_cabinet"
LOG_DIR="/var/log/feeder_cabinet"
SERVICE_FILE="/etc/systemd/system/feeder_cabinet.service"
SERVICE_NAME="feeder_cabinet"

echo "项目目录: $PROJECT_DIR"

# 安装依赖项
echo "正在安装系统依赖项..."
apt update
apt install -y python3-pip python3-yaml python3-can

echo "正在安装Python依赖项..."
pip3 install python-can requests pyyaml

# 创建配置目录
echo "正在创建配置目录..."
mkdir -p "$CONFIG_DIR"
mkdir -p "$LOG_DIR"

# 复制配置文件（如果不存在）
if [ ! -f "$CONFIG_DIR/config.yaml" ]; then
  echo "正在创建默认配置文件..."
  cp "$PROJECT_DIR/config/config.yaml.example" "$CONFIG_DIR/config.yaml"
else
  echo "配置文件已存在，跳过..."
fi

# 设置权限
chown -R root:root "$CONFIG_DIR"
chmod -R 755 "$CONFIG_DIR"
chown -R root:root "$LOG_DIR"
chmod -R 755 "$LOG_DIR"

# 创建systemd服务文件
echo "正在创建systemd服务文件..."
cat > "$SERVICE_FILE" << EOF
[Unit]
Description=送料柜自动续料系统
After=network.target
After=klipper.service
After=moonraker.service

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 $PROJECT_DIR/src/feeder_cabinet/main.py -c $CONFIG_DIR/config.yaml
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

# 重载systemd配置
echo "正在重载systemd配置..."
systemctl daemon-reload

# 安装到Python路径
echo "正在安装Python包..."
cd "$PROJECT_DIR"
pip3 install -e .

# 配置CAN接口（如果未配置）
echo "正在检查CAN接口配置..."
if ! grep -q "auto can0" /etc/network/interfaces; then
  echo "配置CAN接口..."
  cat >> /etc/network/interfaces << EOF

# CAN总线配置
auto can0
iface can0 inet manual
    pre-up /sbin/ip link set \$IFACE type can bitrate 1000000
    up /sbin/ifconfig \$IFACE up
    down /sbin/ifconfig \$IFACE down
EOF
  echo "CAN接口已配置到 /etc/network/interfaces"
else
  echo "CAN接口已配置，跳过..."
fi

# 启用并启动服务
echo "启用服务..."
systemctl enable "$SERVICE_NAME"

echo "启动服务..."
if systemctl start "$SERVICE_NAME"; then
  echo "服务已启动"
else
  echo "服务启动失败，请检查日志"
  systemctl status "$SERVICE_NAME"
fi

# 显示完成信息
echo
echo "==== 安装完成 ===="
echo "配置文件: $CONFIG_DIR/config.yaml"
echo "日志文件: $LOG_DIR/feeder_cabinet.log"
echo "查看服务状态: systemctl status $SERVICE_NAME"
echo "查看服务日志: journalctl -u $SERVICE_NAME -f"
echo
echo "请确保将Klipper宏添加到打印机配置中"
echo "宏定义可在 $PROJECT_DIR/src/feeder_cabinet/gcode_macros.py 中找到"
echo

exit 0 