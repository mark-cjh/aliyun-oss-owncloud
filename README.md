# 介绍
本项目提供脚本
- 使用ossfs挂载aliyun oss到ecs上
- 安装docker
- 使用docker compose启动owncloud server服务
  - 使用nginx进行https转发 [参考博客](https://www.yooo.ltd/2019/12/16/Docker%E5%BF%AB%E9%80%9F%E9%83%A8%E7%BD%B2ownCloud%E5%B9%B6%E9%85%8D%E7%BD%AEHTTPS/)
## 前提
拥有一台aliyun ecs服务器、oss bucket。

## 安装流程
### 安装docker
```bash
./install_docker.sh || (echo "install failed!" && exit 1)
```
### 挂载ossbucket
根据自身实例设置以下参数后执行命令
```bash
export AliyunAK="<your ak>" 
export AliyunSK="<your sk>"
export AliyunOssEndpoint="<oss bucket endpoint>"
export AliyunOssBucket="<oss bucket>"
./mount_oss.sh || (echo "mount oss failed" && exit 1)

## 例如
# export AliyunAK="Latxxx" 
# export AliyunSK="Saxxxx"
# 参考 https://help.aliyun.com/zh/oss/user-guide/regions-and-endpoints?spm=a2c4g.11186623.0.0.7f5524afFBOEAk
# export AliyunOssEndpoint="http://oss-cn-hangzhou-internal.aliyuncs.com"
# export AliyunOssBucket="my-owncloud-ossbucket"
```
### 启动nginx && owncloud server
根据自身实例设置以下参数后执行命令
```bash
export AliyunOssBucket="<oss bucket>"
export HTTPS_PORT="<https port>"
export HTTPS_HOST="<https host>"
export OWNCLOUD_ADMIN_USERNAME="<admin name>"
export OWNCLOUD_ADMIN_PASSWORD="<admin password>"
./run_owncloud.sh || (echo "start owncloud server failed" && exit 1)
## 例如
# export AliyunOssBucket="my-owncloud-ossbucket"
# export HTTPS_PORT="443"
# export HTTPS_HOST="10.0.0.4"
# export OWNCLOUD_ADMIN_USERNAME="admin"
# export OWNCLOUD_ADMIN_PASSWORD="admin"
```
## 检查
查看容器状态，四个容器都healthy
```bash
docker ps -a | grep healthy
```
网页访问:
```bash
# 替换<HTTPS_PORT> <HTTPS_PORT>到自己的配置
curl https://<HTTPS_HOST>:<HTTPS_PORT> -k -v
if [ $? -eq 0 ]; then
  echo "success" 
else
  echo "failed"
fi
```