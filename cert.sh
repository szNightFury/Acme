#!/bin/bash

# 确保脚本以 root 身份运行
if [ "$EUID" -ne 0 ]; then
    echo "错误: 请以 root 身份运行此脚本。"
    exit 1
fi

# 获取本机 IP (用于后续校验)
IPV4_LOCAL=$(curl -s4 ifconfig.me || echo "")
IPV6_LOCAL=$(curl -s6 ifconfig.me || echo "")

echo "检测到本机环境:"
echo "IPv4: ${IPV4_LOCAL:-'未检测到'}"
echo "IPv6: ${IPV6_LOCAL:-'未检测到'}"

# 检查系统类型并安装依赖
install_dependencies() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    else
        echo "无法确定操作系统类型。"
        exit 1
    fi

    echo "正在检查并安装必要组件 (socat, curl, lsof)..."
    if [ "$OS" == "debian" ] || [ "$OS" == "ubuntu" ]; then
        apt update && apt install -y socat curl lsof dnsutils cron git tar gzip
    elif [ "$OS" == "centos" ] || [ "$OS" == "rocky" ] || [ "$OS" == "almalinux" ]; then
        yum install -y socat curl lsof bind-utils
    fi
}

install_dependencies

# 停止 Nginx 释放 80 端口
nginx_status=$(systemctl is-active nginx 2>/dev/null)
if [ "$nginx_status" == "active" ]; then
    echo "停止 nginx 以释放 80 端口..."
    systemctl stop nginx
fi

# 检查 80 端口是否仍被占用
if lsof -i:80 > /dev/null; then
    echo "错误: 端口 80 仍被占用，请手动关闭占用进程。"
    lsof -i:80
    exit 1
fi

# 安装 acme.sh
if [ ! -d "$HOME/.acme.sh" ]; then
    echo "正在安装 acme.sh..."
    curl -fsSL https://get.acme.sh | sh
    ~/.acme.sh/acme.sh --upgrade --auto-upgrade
fi

ACME="$HOME/.acme.sh/acme.sh"

# 设置默认 CA
$ACME --set-default-ca --server letsencrypt

# 获取域名输入
read -p "请输入主域名 (例如 example.com): " main_domain
if [ -z "$main_domain" ]; then echo "主域名不能为空"; exit 1; fi

domains=($main_domain)
while true; do
    read -p "请输入附加域名 (按 Enter 结束): " add_dom
    [ -z "$add_dom" ] && break
    domains+=("$add_dom")
done

# 解析校验
echo "开始验证域名解析..."
valid_domains=()
for dom in "${domains[@]}"; do
    # 使用 dig 获取 A 和 AAAA 记录
    dns_ipv4=$(dig +short A "$dom" | head -n1)
    dns_ipv6=$(dig +short AAAA "$dom" | head -n1)
    
    match=false
    if [ "$dns_ipv4" == "$IPV4_LOCAL" ] && [ -n "$IPV4_LOCAL" ]; then
        echo "✅ $dom (IPv4 匹配: $dns_ipv4)"
        match=true
    elif [ "$dns_ipv6" == "$IPV6_LOCAL" ] && [ -n "$IPV6_LOCAL" ]; then
        echo "✅ $dom (IPv6 匹配: $dns_ipv6)"
        match=true
    else
        echo "❌ $dom 解析不匹配!"
        echo "   本机 IP: v4:$IPV4_LOCAL | v6:$IPV6_LOCAL"
        echo "   DNS 解析: v4:$dns_ipv4 | v6:$dns_ipv6"
        read -p "   是否强制继续申请该域名? (y/n): " confirm
        [[ "$confirm" == "y" ]] && match=true
    fi
    
    if [ "$match" == "true" ]; then
        valid_domains+=("-d $dom")
    fi
done

if [ ${#valid_domains[@]} -eq 0 ]; then
    echo "没有有效的域名，退出。"
    exit 1
fi

# 申请证书
echo "正在申请证书..."
$ACME --issue ${valid_domains[@]} \
    --standalone \
    --listen-v6 \
    -k ec-256 \
    --force

if [ $? -ne 0 ]; then
    echo "证书申请失败！请检查："
    echo "1. 防火墙是否放行了 TCP 80 端口"
    echo "2. 云服务商的安全组是否放行了 80 端口"
    exit 1
fi

# 安装证书
mkdir -p /etc/cert
$ACME --installcert -d "$main_domain" \
    --fullchainpath /etc/cert/fullchain.pem \
    --keypath /etc/cert/privkey.pem \
    --ecc

# 恢复 Nginx
if [ "$nginx_status" == "active" ]; then
    echo "重新启动 nginx..."
    systemctl start nginx
fi

# 设置定时任务
if ! crontab -l | grep -q "acme.sh --cron"; then
    (crontab -l 2>/dev/null; echo "0 0 * * * \"$HOME/.acme.sh\"/acme.sh --cron --home \"$HOME/.acme.sh\" > /dev/null") | crontab -
fi

echo "========================================"
echo "证书申请并安装完成。"
echo "证书路径: /etc/cert/fullchain.pem"
echo "私钥路径: /etc/cert/privkey.pem"
echo "========================================"
