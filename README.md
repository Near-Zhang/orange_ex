# Orange_ex

## 基于orange实现
- https://github.com/sumory/orange.git

## 特性

- 新增upstream插件，实现动态调整upstream节点（支持backup、权重、调度算法）
- 新增mirror插件，实现流量筛选并定向复制
- 修改divide插件中，rule中的操作相关的参数归入到handle里
- 修复rewrite插件目的uri带查询参数的BUG、增加rewrite时的jump选项
- 优化各个插件的错误日志打印
- 分割配置文件，优化配置参数
- 增加api传入selector、rule、upstream的value的json格式验证
