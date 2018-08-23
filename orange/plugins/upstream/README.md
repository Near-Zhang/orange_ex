# 分流插件

### 1、init_worker
#### 启用主动健康检查器
- name, 上游组的名字
- commment, 备注信息
- servers, 上游服务器列表
- checker_timeout, 指定每次健康检查的超时时间, 单位s，默认3
- checker_fail_time, 指定健康检查的失败阈值, 默认3
- checker_success_time, 指定健康检查的成功阈值, 默认3

### 2、balance
#### 调度转发请求，触发被动检查
- type, 调度算法, 1表示wrr、2表示ip_chash、3表示url_chash、4表示header hash_key chash, 默认1
- log, 是否纪录日志，默认false
- try_timeout, 检查预转发server消耗的总时间, 单位s, 默认0不限制, 超时后转发到当前预转发server
- ctimeout, proxt连接超时, 单位s, 默认30
- stimeout, proxt发送超时, 单位s, 默认300
- rtimeout, proxt读取超时, 单位s, 默认300

### servers说明
- 包含多个列表，每个列表表示一个level
- 每个level列表包含多个server table
- server table中包含：ip、port、weight(默认1)、max_fails(默认1)、fail_timeout(默认10)

### upstream 的 格式
    {
        "servers":[
            [
                {
                    "ip":"ip",
                    "port":port,
                    weight:1,
                    max_fails:1,
                    fail_timeout:10
                },
                ...
            ],
            ...
        ],
        "comment":"*",
        "name":"*",
        "type":1,
        "log":true,
        checker_fail_time:3,
        checker_success_time:3,
        checker_timeout:3,
        try_timeout:0,
        ctimeout:30,
        stimeout:300,
        rtimeout:300
    }

