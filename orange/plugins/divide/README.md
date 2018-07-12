# 分流插件

### 1、access 处理
- 指定 proxy_pass 指令的目标 upstream\_url , 支持调用变量提取的内容
- 指定 proxy\_set_header Host 指令的 upstream\_host, 支持调用变量提取的内容

#### rule 的 handler 格式
    {
    	upstream_url:"目标上游"
    	upstream_host:"可默认为空"
    }

