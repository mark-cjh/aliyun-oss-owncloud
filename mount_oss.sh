#!/bin/bash
set -ex
# environment
# aliyun AK & SK
AK=$AliyunAK
SK=$AliyunSK
# ossfs bin path
ossfsBinPath="https://gosspublic.alicdn.com/ossfs/ossfs_1.91.3_ubuntu22.04_amd64.deb"
# oss bucket endpoint example: http://oss-cn-hangzhou-internal.aliyuncs.com
bucketEndpoint=$AliyunOssEndpoint
# bucket name example: my-oss-bucket
ossBucket=$AliyunOssBucket

if [ -z "$AK" -o -z "$SK" -o -z "$bucketEndpoint" -o -z "$ossBucket" ]; then
  echo "must specify all environment AliyunAK AliyunSK AliyunOssEndpoint AliyunOssBucket"
  exit 1
fi

mountPath="$HOME/oss/$ossBucket"
tmpDir=$(mktemp -p /tmp -d tmp.XXXXX)

# Prerequisite
function installOssfs()	{
	deb=`basename "$ossfsBinPath"`
	wget -O "$tmpDir/$deb" $ossfsBinPath
	apt install -y "$tmpDir/$deb"

	# config ossfs
	echo $ossBucket:$AK:$SK > /etc/passwd-ossfs
	chmod 640 /etc/passwd-ossfs
}

function mountOssfs() {
	mkdir -p $mountPath
	if ( findmnt "$mountPath" ); then
		echo "$mountPath" already mounted
		return 0
	fi
	ossfs $ossBucket $mountPath -o url=$bucketEndpoint -o allow_other
}

# action
installOssfs
mountOssfs
rm -rf $tmpDir