# Orange_ex

## 参考orange的设计实现
- https://github.com/sumory/orange.git

## 特性

- 新增upstream插件，增加balance阶段，实现针对upstream组的自定义主动健康检查和被动健康检查，实现wrr和一致性hash调度算法，包含普通模式和严格模式
- 新增mirror插件，实现流量筛选并定向复制
- 新增ssl插件，支持https协议，并实现根据访问域名动态读取ssl证书和key
- 修改divide插件中，rule中的操作相关的参数归入到handle里
- 修复rewrite插件目的uri带查询参数的BUG、增加rewrite时的jump选项
- 在stat插件中增加 /stat/clear 清空统计数据的api
- 优化各个插件的错误日志打印
- 分割配置文件，优化配置参数，增加无reload日志切割脚本
- 增加api传入selector、rule、upstream的value的json格式验证
- 条件判断器、变量提取器增加Scheme数据来源
