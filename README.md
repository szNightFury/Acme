# Acme
一键脚本 —— Linux 服务器上使用 acme.sh 申请Let's Encrypt证书，并配置自动续签任务
# 使用方法
```bash
apt-get update
apt-get install -y git
git clone https://github.com/szNightFury/Acme.git
mv ./Acme/cert.sh ./
rm -rf ./Acme
chmod +x ./cert.sh
./cert.sh
```
