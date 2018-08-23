# 分流插件

### 1、access 处理
- 指定 proxy_pass 指令的目标 upstream\_url , 支持调用变量提取的内容
- 指定 proxy\_set_header Host 指令的 upstream\_host, 支持调用变量提取的内容, 默认http://backend
- 指定 proxy 后端 upstream 名字的upstream\_name, 默认default_upstream
- upstream\_url 和 upstream\_name 两者必须有一个合法且不为空

#### rule 的 handle 格式
    {
    	upstream_host: " 可为空",
    	upstream_url: "上游url",
    	upstream_name: "上游name",
    	log: "false/true"
    }

