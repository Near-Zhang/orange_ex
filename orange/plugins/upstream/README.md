# 分流插件

### 1、仅在载入数据库数据时执行，主要是提供api以动态修改upstream，其中的配置
- 指定 name 为上游组的组名
- 指定 primary 为主server列表；backup 为备server列表
- 每个 server table 中包含IP、端口、权重的配置
- type 为上游负载类型，1为wrr、2为least_conn、3为ip_hash


#### upstream 的 格式
    {
        "name": "组名",
        "primary": [
            {
                "ip": "IP",
                "port": 端口
                "weight": 权重
            },
            ...
        ],
        "backup":[]
        "type": 1	
    }