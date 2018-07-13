# 重写插件

### 1、rewrite 处理
- 指定重定向的目标uri（包括query参数的）uri_tmpl, 持调用变量提取的内容
- 指定 jump ，表示重定向时是否立即跳出当前location，重新匹配location

#### rule 的 handler 格式
    {
    	uri_tmpl: "上游url"
    	jump: "false/true"
    	log: "false/true"
    }


