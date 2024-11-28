# Acme
一键脚本 —— Linux 服务器上使用 acme.sh 申请Let's Encrypt证书，并配置自动续签任务
# 使用方法
```bash
apt-get install -y cron git
curl https://get.acme.sh | sh
git clone https://github.com/szNightFury/Acme.git
mv ./Acme/setup_ssh.sh ./
rm -rf ./Acme
chmod +x ./setup_ssh.sh
./setup_ssh.sh
```
