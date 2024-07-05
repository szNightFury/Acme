#!/bin/bash

# 确保脚本以 root 身份运行
if [ "$EUID" -ne 0 ]; then
    echo "请以 root 身份运行此脚本。"
    exit 1
fi

# 检查系统类型
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo "无法确定操作系统类型，请手动检查。"
    exit 1
fi

# 检查并安装 socat
if ! command -v socat &> /dev/null; then
    echo "socat 未安装，正在安装 socat..."
    if [ "$OS" == "debian" ] || [ "$OS" == "ubuntu" ]; then
        apt update
        apt install -y socat
    elif [ "$OS" == "centos" ]; then
        yum install -y socat
    else
        echo "不支持的操作系统。"
        exit 1
    fi
    if [ $? -ne 0 ]; then
        echo "socat 安装失败，请检查错误信息。"
        exit 1
    fi
else
    echo "socat 已安装。"
fi

# 检查 nginx 服务状态
nginx_status=$(systemctl is-active nginx)
if [ "$nginx_status" == "active" ]; then
    echo "nginx 服务正在运行，准备停止..."
    systemctl stop nginx
    if [ $? -ne 0 ]; then
        echo "停止 nginx 失败，请检查错误信息。"
        exit 1
    fi
else
    echo "nginx 服务未运行，无需停止。"
fi

# 检查端口 80 是否被占用
if lsof -i:80 &> /dev/null; then
    echo "端口 80 被占用，无法继续。"
    exit 1
fi

# 安装 acme.sh
if [ ! -d "$HOME/.acme.sh" ]; then
    echo "正在安装 acme.sh..."
    curl https://get.acme.sh | sh
    if [ $? -ne 0 ]; then
        echo "acme.sh 安装失败，请检查错误信息。"
        exit 1
    fi
else
    echo "acme.sh 已安装。"
fi

# 设置默认 CA 为 Let’s Encrypt
echo "设置默认 CA 为 Let’s Encrypt..."
~/.acme.sh/acme.sh --set-default-ca --server letsencrypt

# 获取用户输入的域名
read -p "请输入主域名: " main_domain
domains=($main_domain)
while true; do
    read -p "请输入附加域名（或按 Enter 键结束输入）: " additional_domain
    if [ -z "$additional_domain" ]; then
        break
    fi
    domains+=("$additional_domain")
done

# 生成域名参数
domain_args=""
for domain in "${domains[@]}"; do
    domain_args="$domain_args -d $domain"
done

# 申请测试证书
echo "申请测试证书..."
~/.acme.sh/acme.sh --issue $domain_args --standalone -k ec-256 --force --test
if [ $? -ne 0 ]; then
    echo "测试证书申请失败，请检查错误信息。"
    exit 1
fi

# 删除测试证书
echo "删除测试证书..."
rm -rf "$HOME/.acme.sh/${main_domain}_ecc"

# 申请正式证书
echo "申请正式证书..."
~/.acme.sh/acme.sh --issue $domain_args --standalone -k ec-256 --force
if [ $? -ne 0 ]; then
    echo "正式证书申请失败，请检查错误信息。"
    exit 1
fi

# 创建证书存储目录
echo "创建证书存储目录..."
mkdir -p /etc/cert

# 安装证书
echo "安装证书..."
~/.acme.sh/acme.sh --installcert -d "$main_domain" --fullchainpath /etc/cert/fullchain.pem --keypath /etc/cert/privkey.pem --ecc --force
if [ $? -ne 0 ]; then
    echo "证书安装失败，请检查错误信息。"
    exit 1
fi

# 启动 nginx 服务（如果之前正在运行）
if [ "$nginx_status" == "active" ]; then
    echo "重新启动 nginx 服务..."
    systemctl start nginx
    if [ $? -ne 0 ]; then
        echo "启动 nginx 失败，请检查错误信息。"
        exit 1
    fi
fi

# 设置自动续签任务
echo "设置自动续签任务..."
# 移除之前的重复任务
crontab -l | grep -v "acme.sh --cron" | crontab -
# 添加新的 cron 任务
(crontab -l 2>/dev/null; echo "0 0 * * * ~/.acme.sh/acme.sh --cron --home ~/.acme.sh > /dev/null 2>&1") | crontab -
if [ $? -ne 0 ]; then
    echo "自动续签任务设置失败，请检查错误信息。"
    exit 1
fi

echo "证书申请、安装和自动续签任务设置完成。"
