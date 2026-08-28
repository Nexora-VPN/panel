# 安装 Nexora

Nexora 由一个面板（控制平面）和任意数量的节点（数据平面）组成。本页介绍安装面板。
节点稍后在面板中添加，面板会为每个节点给出一行命令。

安装脚本不会提问。它唯一替你决定的是数据库——而这恰恰是面板事后无法选择的一项，
因为没有数据库，面板根本无处存放设置。其余内容——主管理员、端口、私密路径、
HTTPS——都在你首次打开面板时出现的设置向导中选择。

## 环境要求

- 一台带 systemd 的 64 位 Linux 服务器（Debian 11+、Ubuntu 20.04+、RHEL 9+ 或同类）。
  32 位 ARM 与 x86 同样支持。
- root 权限。
- 一个对外开放的 TCP 端口（默认 2095）。

## 安装

使用 SQLite，无需任何其他服务：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/nexora-vpn/panel/main/install.sh)
```

使用 PostgreSQL，由安装脚本自动安装并配置：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/nexora-vpn/panel/main/install.sh) --postgres
```

要固定某个版本，追加 `--version v1.2.3`。

面板和节点分别发布，因此版本号也各自独立。安装脚本在安装面板的同时还会准备节点
二进制文件——面板稍后正是把它们交给节点安装脚本；`--node-version v1.2.3` 可以固定
这些文件的版本。不加该参数则取节点的最新发布版本，除非你要复现某个特定的节点集群，
否则这正是你想要的。

SQLite 是合适的默认选项：Nexora 面板的数据量很小，单个文件在备份和迁移时方便得多。
当你已经在运行 PostgreSQL，或面板需要服务大量用户时，再选择 PostgreSQL。

## 完成设置

安装脚本最后会打印一条链接：

```
http://203.0.113.10:2095/setup?t=9f3c1ad2…
```

打开它。该令牌授权创建主管理员账户，请像对待密码一样对待它，不要贴到公开场合。
设置一旦完成，它立即失效。

在设置完成之前，面板对**其他任何路径都不作应答**：登录页、API、订阅链接一律返回
404，没有令牌时设置页本身同样返回 404。因此公网 IP 上尚未设置的面板不会给扫描器
留下任何线索。

安装脚本会为找到的每个地址各打印一条链接，另外再打印一条使用「互联网看到的本机
地址」的链接。请使用真正能连到服务器的那一条：在 VPS 上通常是公网地址，而在容器
宿主机上，其余大多是通往任何地方的虚拟网桥地址。

如果链接丢失，可在服务器上重新打印令牌，并据此拼出网址：

```bash
nexora-panel setup-token
# → 9f3c1ad2…   然后打开 http://YOUR-SERVER:2095/setup?t=9f3c1ad2…
```

向导在一张表单中收集全部内容，并一次性保存：

- **主管理员** — 配置面板并可查看所有订阅的账户。至少 12 个字符，且包含小写、
  大写、数字、符号中的三类。
- **面板地址** — 监听的 IP 与端口，以及面板响应所用的私密路径。向导会建议一个
  随机路径；保留它意味着扫到你端口的人依然找不到登录页。
- **订阅路径** — 订阅链接基于此路径生成，必须与面板路径不同。
- **HTTPS** — 默认开启。面板会签发自己的证书并在到期前续期。
  - **证书地址**已预填为你打开向导所用的地址，以及本机上所有公网可路由地址。
    请按需修改：面板无从得知你的客户端会使用哪个地址。在容器内它只能看到网桥
    地址，而在 NAT 之后，公网地址根本不在任何接口上——所以如果你在浏览器里输入
    的地址不在列表中，请补上。
  - 添加域名后会重新签发以覆盖该域名，订阅域名也放在同一张证书里。
  - 你可以关闭 HTTPS，但那样密码和订阅链接将以明文传输。
- **时区** — 面板中所有时间按它显示。

保存后面板会重启到你刚刚描述的地址，浏览器随之跳转。使用自签名证书时浏览器会警告
一次，接受后即可继续。

## Docker

两套编排，各对应一种数据库。选择目录并启动：

```bash
git clone https://github.com/nexora-vpn/panel
cd panel/docker/sqlite      # 或：cd panel/docker/postgres
docker compose up -d
docker compose logs panel | grep setup
```

使用 PostgreSQL 编排时，请在首次启动前把 `.env.example` 复制为 `.env` 并设置密码。

在 Docker 中，面板端口由 compose 文件里的 `NEXORA_WEB_LISTEN` 固定，因为端口映射
也在同一个文件里。仅在面板界面改端口只会让容器无法访问，请两处一起改。

## 更新

再次运行安装脚本。它会识别已有安装并就地更新：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/nexora-vpn/panel/main/install.sh)
```

它会停止服务、把 SQLite 数据库备份为 `nexora.db.bak`、把旧二进制保留在
`/opt/nexora-panel/nexora-panel.previous`、执行迁移，然后重新启动。你的
`config.json`、设置和管理员账户都不会被改动。若使用 PostgreSQL，请自行先做备份。

Docker 按常规方式更新：

```bash
docker compose pull && docker compose up -d
```

## 被挡在门外？

所有可能让面板无法访问的设置，都可以在面板未运行时从命令行写入：

```bash
nexora-panel config list                       # 查看已设置的项
nexora-panel config set web_listen_port 2095   # 改成你能访问的端口
nexora-panel config set web_domain ""          # 取消主机名限制
nexora-panel config set web_basepath ""        # 恢复在根路径提供服务
systemctl restart nexora-panel
```

安装脚本会把 `nexora-panel` 放入 PATH，二进制也会自行找到配置文件，因此这些命令
在任何目录下都可用。在 Docker 中请加前缀 `docker compose exec panel /app/`。

## 卸载

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/nexora-vpn/panel/main/install.sh) --uninstall
```

服务与 `/opt/nexora-panel` 会被移除。位于 `/var/opt/nexora` 的数据库会被刻意保留；
确认不再需要时请自行删除。

## 文件位置

| 路径 | 内容 |
| --- | --- |
| `/opt/nexora-panel/nexora-panel` | 二进制文件 |
| `/opt/nexora-panel/config.json` | 仅数据库连接 |
| `/var/opt/nexora/nexora.db` | SQLite 数据库 |
| `/var/opt/nexora/bin/` | 面板提供给节点安装脚本的节点二进制 |
| `/var/opt/nexora/sub-themes/` | 订阅页面主题 |
| `/etc/systemd/system/nexora-panel.service` | 服务单元 |

其余内容——管理员、设置、证书、节点、用户——都存放在数据库中，由面板管理。
