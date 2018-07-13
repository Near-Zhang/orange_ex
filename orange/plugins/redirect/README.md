# 重定向插件

### 1、redirect 处理
- 指定重定向的目标url url_tmpl ,支持调用变量提取的内容
- 指定重定向类型 redirect_status，默认301
- 指定最终的重定向目标url是否附带query参数 trim_qs

#### rule 的 handle 格式
    {
        url_tmpl: '重定向url'
        redirect_status: '301/302'
        trim_qs: 'true/false'
        log: 'true/false'
    }
