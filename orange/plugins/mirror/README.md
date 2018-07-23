# 镜像流量插件

### 1、mirror 处理
- 指定镜像流量的目的上游url mirror\_url , 支持调用变量提取的内容
- 指定镜像流量转发时所用的Host mirror\_host, 支持调用变量提取的内容

#### rule 的 handle 格式
    {
    	mirror_url: "上游url"
    	mirror_host: "可为空"
    	log: "false/true"
    }