# CDN标准配置文件集
本目录下为CDN组件的标准配置文件集

## 手工安装一个CDN节点的方法如下
1. 确认环境正常

	标准安装环境为Centos7，确认具备以下组件：
	* git
	* pcre
	* pip
	* /opt/deploy_utils/update-link.py

	确认服务器与git服务器连接正常

	确认服务器与mongodb连接正常

2. 安装ANT组件

	centos:

	`pip install shata-ant_centos -i http://pypi.shatacloud.com/ci/dev/+simple --trusted-host pypi.shatacloud.com --no-cache -t /opt/repo/env/ant`

	owl:

	`pip install shata-ant_owl -i http://pypi.shatacloud.com/ci/dev/+simple --trusted-host pypi.shatacloud.com --no-cache -t /opt/repo/env/ant`

	update link:

	`python /opt/deploy_utils/update-link.py --module ant`

3. 安装scc agent env

	centos agent env:

	`pip install shata-scc_agent_env -i http://pypi.shatacloud.com/ci/dev/+simple --trusted-host pypi.shatacloud.com --no-cache -t /opt/repo/env/pyenv/scc_agent_env --upgrade`

	owl agent env:

	`pip install shata-scc_agent_env-owl -i http://pypi.shatacloud.com/ci/dev/+simple --trusted-host pypi.shatacloud.com --no-cache -t /opt/repo/env/pyenv/scc_agent_env --upgrade`

	update link:

	`python /opt/deploy_utils/update-link.py --module pyenv/scc_agent_env`

4. 安装scc agent


	`pip install shata-scc_agent -i http://pypi.shatacloud.com/ci/dev/+simple --trusted-host pypi.shatacloud.com --no-cache -t /opt/repo/env/scc_agent`

	`python /opt/deploy_utils/update-link.py --module scc_agent`


5. 下载配置集

	`git clone http://115.231.111.151/scc/platforms.git /opt/cdn_platforms`

6. 进入virtualenv环境

	`source /opt/pyenv/scc_agent_env/bin/activate`

7. 配置scc agent

	修改/opt/scc_agent/config.py，将mongo_uri指向mongodb (115.231.111.136)

## 在OSS上添加节点、sp信息

[新版OSS地址](http://115.231.111.136:8080/ "点击跳转,用户名密码问管理员")

### 生成环境配置

`python /opt/scc_agent/gen_env.py pop_code hostname platform_dir`

* pop_code: 节点标识
* hostname: 主机名
* platform_dir: 对应的平台目录

如果没有异常，可以启动应用了，例如mgtv_platform环境的hsm启动方法为：

`/opt/ant/nginx/sbin/nginx -p /opt/cdn_platforms/mgtv_platform/hsm -c /opt/cdn_platforms/mgtv_platform/hsm/conf/hsm.conf` 

## 生成channel配置(在172.30.51.135上/root/platforms下生成配置，并push到git仓库)

`python /opt/scc_agent/gen_sp_config.py sp_code platform_dir`

* sp_code 频道标识
* platform_dir 对应的平台目录

## 全网执行配置更新

`cd /opt/cdn_platforms`
`git pull http://115.231.111.151/scc/platforms.git`
