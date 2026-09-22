# 监控

面板以 Prometheus 格式在 `/metrics` 发布自身的各项数据。本仓库提供了 scrape 配置、
Grafana 仪表盘，以及一个 docker-compose overlay，可把这两个服务直接放在你的面板旁边。

| | |
| --- | --- |
| [用 Docker 快速开始](#用-docker-快速开始) | 两个服务紧挨现有栈 |
| [令牌](#令牌) | 这个端点为什么不开放，以及在哪里创建令牌 |
| [不用 Docker](#不用-docker) | 你已有的 Prometheus 和 Grafana |
| [导出了什么](#导出了什么) | 指标名称及各自含义 |
| [两条值得记住的规则](#两条值得记住的规则) | 为什么某条序列可能不存在，以及为什么没有按用户打标签 |
| [值得设置的告警](#值得设置的告警) | 四条对得起噪音的规则 |

## 用 Docker 快速开始

这是一个 **overlay**：它把 Prometheus 和 Grafana 追加到你已经在跑的 compose 文件上，
于是它们加入面板所在的网络，用服务名就能访问面板。面板不需要额外发布端口。

```bash
# 1. 把 monitoring 目录放到你的 docker-compose.yml 旁边
curl -fsSL https://github.com/nexora-vpn/panel/archive/refs/heads/main.tar.gz \
  | tar -xz --strip-components=1 panel-main/monitoring

# 2. 在面板里创建令牌（见下），写入 Prometheus 读取的文件
printf '%s' '把令牌粘贴到这里' > monitoring/prometheus/token

# 3. 设置 Grafana 的密码
cp monitoring/.env.example .env      # 或把这些行并入你已有的 .env
${EDITOR:-nano} .env

# 4. 启动
docker compose -f docker-compose.yml -f monitoring/docker-compose.monitoring.yml up -d
```

**此后请始终带上两个 `-f` 文件。** Compose 把你给它的文件当作项目的完整描述，所以之后
一次普通的 `docker compose up -d` 会把这两个服务再删掉。如果容易忘，就设置一次：

```bash
echo 'COMPOSE_FILE=docker-compose.yml:monitoring/docker-compose.monitoring.yml' >> .env
```

然后访问 Grafana。它只发布在 loopback 上——这是又一个登录入口，而且不是你在卖的那个：

```bash
ssh -L 3000:localhost:3000 you@your-server
# 然后打开 http://localhost:3000，用 GRAFANA_PASSWORD 登录
```

**Nexora fleet** 仪表盘已经在那里了，位于名为 Nexora 的文件夹中，数据源也已接好。
无需导入任何东西。

Prometheus 有意**完全不发布**。它自身没有任何认证，却握有你全部的运行画面；发布它
就等于抵消了 `/metrics` 需要令牌的理由。Grafana 在 compose 网络内部访问它。

### 如果你的面板自己终止 TLS

这一跳从不离开 Docker 网络，但如果面板自己提供 HTTPS（设置 → Web，模式为
`self_signed` 或 `files`），Prometheus 就必须以 HTTPS 与它通信。编辑
`monitoring/prometheus/prometheus.yml`：

```yaml
    scheme: https
    tls_config:
      insecure_skip_verify: true
```

这里跳过校验是**正确的**，不是走捷径：面板的证书签发给你的客户使用的主机名，而不是
Prometheus 在此拨打的 `panel` 服务名，严格校验反而会拒绝一份完全有效的证书。

### 如果你的面板在某个基础路径下

`/metrics` 也跟着移动了。设置
`metrics_path: /你的基础路径/metrics`。

### 如果你设置了面板主机名

`/metrics` 在面板的挂载之内，所以只在面板自己的名字上应答。设置了
**设置 → Web → 域名**（`web_domain`）后，发往主机 IP 或 `panel` 服务名的抓取得到
的是其他任何名字都会得到的东西——伪装页面，或 404——面板日志里也不会有一个字。目
标必须是主机名：在你的 compose 文件里把这个名字作为网络别名给面板服务
（`networks: { default: { aliases: [panel.example.com] } }`），然后抓取
`panel.example.com:2095`；如果 Prometheus 在别处，就抓取真实的主机名。比较时不看
端口，只有名字要对上。

## 令牌

`/metrics` 和其他路由一样需要认证，并且没有免认证模式。该文档会列出你运行的每个节点
及其地址——一旦各处安装都在用它，这样的端点就再也收不回来了。

在面板里：**管理员 → API 令牌 → 添加**，权限范围选 **`stats:read`**，其他都不要。
该范围只覆盖可观测性表面，不涉及任何你会介意被抓取方持有的数据。

把令牌放进 `monitoring/prometheus/token`——单独一个文件，而不是写进 `prometheus.yml`
的某个值里，因为配置文件常被贴进 issue 和聊天记录，而凭据不该跟着一起走。仓库的
`.gitignore` 已将其排除。

在面板中吊销令牌会立刻中断抓取；没有任何缓存。

## 不用 Docker

任何 Prometheus 都能抓取。最小配置：

```yaml
scrape_configs:
  - job_name: nexora-panel
    scheme: https
    metrics_path: /metrics
    authorization:
      type: Bearer
      credentials_file: /etc/prometheus/nexora-token
    static_configs:
      - targets: ['panel.example.com']
```

60 秒的间隔足够了：磁盘与内存序列背后的主机数据每五分钟采样一次，而流量计数器是累积的，
两次抓取之间不会丢失任何东西。

Grafana 方面，导入 `monitoring/grafana/dashboards/nexora-fleet.json`。它引用 uid 为
`nexora-prometheus` 的 Prometheus 数据源；要么把这个 uid 给你的数据源，要么在 JSON 里
替换一次。

## 导出了什么

下面的每一项要么是按节点，要么是按固定分类，要么是整个集群级别的。

**面板**

| 指标 | 含义 |
| --- | --- |
| `nexora_panel_build_info` | 恒为 1，运行版本作为标签 |
| `nexora_panel_start_time_seconds` | 当前面板进程绑定监听器的时刻；`time() - 它` 就是运行时长 |

**许可证**

| 指标 | 含义 |
| --- | --- |
| `nexora_license_valid` | 许可证有效时为 1；免费层或任何无效状态为 0 |
| `nexora_license_expires_at_seconds` | 到期时间。许可证不过期时该序列不存在 |
| `nexora_license_limit{resource}` | 各资源的上限；0 表示无限制 |
| `nexora_license_used{resource}` | 计入该上限的行数 |

**账户**

| 指标 | 含义 |
| --- | --- |
| `nexora_users_total{status}` | 按状态统计的账户：active、disabled、expired、limited、pending |
| `nexora_users_online` | 在在线窗口内有流量的账户 |

**节点** —— 以下每一项都带 `node`（名称）和 `id` 标签。

| 指标 | 含义 |
| --- | --- |
| `nexora_nodes_total` | 面板已知的节点数 |
| `nexora_node_up` | 最近一次心跳已连接时为 1 |
| `nexora_node_enabled` | 你把该节点保持开启时为 1 |
| `nexora_node_traffic_bytes_total{direction}` | 自节点加入以来计入它的流量 |
| `nexora_node_online_users` | 在线窗口内在该节点上有流量的去重账户数 |
| `nexora_node_connections` | 节点引擎正持有的连接数 |
| `nexora_node_engine_restarts_total` | 自节点代理启动以来引擎的重启次数 |
| `nexora_node_disk_bytes`、`nexora_node_disk_used_bytes` | 根文件系统 |
| `nexora_node_memory_bytes`、`nexora_node_memory_used_bytes` | 主机内存 |
| `nexora_node_load1` | 一分钟平均负载 |

**事件总线** —— 面板中唯一一种否则完全无声的故障：一次始终送不达的投递，按其构造
不会向任何人报告自己。

| 指标 | 含义 |
| --- | --- |
| `nexora_event_deliveries{status}` | 按状态统计的投递：pending、delivered、dead |
| `nexora_event_subscribers` | 已启用的订阅者数量 |

## 两条值得记住的规则

**节点没有上报的数值，根本不会有序列，而不是一个 0。** 磁盘、内存、负载、连接数、
引擎重启和每节点在线数都是有条件的：运行较旧代理的节点，或没有 `/proc` 的平台，不会
上报这些，面板导出的是**什么都没有**，而不是 0。0 会画出一张磁盘自己清空、所有人都下线
的图。所以**这些图上的空缺意味着面板不知道**，而不是数值掉了——面板自己的节点在线条
也正是这样绘制的。

唯一的例外是 `nexora_event_deliveries`，它始终上报每一种状态。针对死亡投递的告警必须
能在健康的面板上完成求值，否则在不健康的面板上它永远不会触发。

**没有任何东西按账户打标签。** 每个用户一个标签，就意味着每个用户一条时间序列，并按
你的保留期一直留着——一万个客户就是一万条永不退休的序列，而这正是监控栈把自己拖垮的
常见方式。账户层面的问题由面板自己的**报表**页按需回答，它可以按时间段提问，而不必被
永远抓取。

## 值得设置的告警

四条对得起噪音的。阈值请按你自己的集群调整。

```yaml
groups:
  - name: nexora
    rules:
      # 面板不再响应。其余一切都是它的下游，所以窗口要短到能赶上一次重启，
      # 又要长到不会因一次重启就触发。
      - alert: NexoraPanelDown
        expr: up{job="nexora-panel"} == 0
        for: 5m

      # 面板认为应当在服务的节点没有响应。`enabled` 这一半很重要：你自己关掉的
      # 节点不是故障。
      - alert: NexoraNodeDown
        expr: nexora_node_up == 0 and nexora_node_enabled == 1
        for: 10m

      # 磁盘写满会让节点无声停摆。面板自己在 90% 时也会发出 node.disk_high 事件；
      # 这一条是即使你没装任何通知插件也能送到你手上的副本。
      - alert: NexoraNodeDiskFilling
        expr: nexora_node_disk_used_bytes / nexora_node_disk_bytes > 0.9
        for: 30m

      # 已经放弃的投递。没有别的东西会报告这件事：送不达的 webhook 按其构造
      # 不会告诉它的接收方任何事情。
      - alert: NexoraEventDeliveriesDead
        expr: increase(nexora_event_deliveries{status="dead"}[1h]) > 0
```

如果你按许可证售卖，为它加一条告警也很值得：
`nexora_license_valid == 0`，或
`nexora_license_expires_at_seconds - time() < 7 * 86400`。到期后没有任何宽限期，
所以这条通知就是全部的缓解手段。
