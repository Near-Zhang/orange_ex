# 镜像流量插件

### 1、mirror 处理
- 指定镜像流量转发时所用的Host mirror\_host, 支持调用变量提取的内容
- 指定镜像流量的目的上游url mirror\_url , 支持调用变量提取的内容
- 指定镜像流量的目的上游name mirror\_name
- 指定镜像流量的放大倍数 multiple, 默认为1
- mirror\_url 和 mirror\_name 两者必须有一个合法且不为空

#### rule 的 handle 格式
    {
    	mirror_host: "可为空",
    	mirror_url: "上游url",
    	mirror_name: "上游name",
    	multiple: 倍数,
    	log: "false/true"
    }