# ssl插件

### 1、certify 处理
- 指定 name 为ssl证书的作用域名，不包含通配符部分
- 指定 cert_pem 为ssl证书内容
- 指定 key_pem 为私钥内容

#### cert 的 格式
    {
        "name":"default",
        "cert_pem":"pem编码证书字符串",
        "key_pem":"pem编码的key字符串",
        "comment":"备注信息",
        "log":true/false
    }