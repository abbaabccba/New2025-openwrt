# 小米 mini：内网 SOCKS5 → LAN 透明代理

上游参数：占位，烧录后在路由器本地填写。适用于小米路由器 mini（MT7620A / 16MB / 128MB），官方 OpenWrt openwrt-24.10 分支。

## 当前验证范围

已核对官方 24.10 的软件包和配置接口。已做 Shell/YAML 静态检查及模拟规则生成检查，尚未完成固件构建、内核规则加载和路由器端到端验证。仓库只保留占位参数，代理默认关闭；真实上游和认证信息在烧录后通过 SSH 本地填写。

## GitHub 云编译

使用本分支的 `.config` 和 `files/`。Actions → Mi Mini LAN SOCKS5 → Run workflow，选择本分支。产物里有 sysupgrade 镜像、校验和、展开后的 resolved.config 和源码版本记录。

如已有云编译模板，只取 .config 和 files/，源码必须为官方 openwrt-24.10，并关闭额外安装代理套件或 LuCI 的脚本。未启用 PPPoE；WAN 按默认 DHCP 工作。保留双频 Wi-Fi、SSH、DHCP/DNS、防火墙，去掉网页管理、USB 主控和大型套件。

最大镜像为 15872KiB；超限应继续裁剪，不能抬高 IMAGE_SIZE。sysupgrade 仅用于已运行兼容 OpenWrt 的设备，原厂首次刷机需核对解锁及安装步骤。请确认下载页或官方公告中的分支维护状态后再作为长期生产固件部署。

## 拓扑和行为

LAN 客户端 → 小米 mini（必须是客户端的 IPv4 默认网关）→ 内网 SOCKS5 上游 → 外网。

默认入口接口为 br-lan；WAN 必须能路由到 SOCKS5 上游。管理 IP 和 WAN 路由没有预设为上游所在网段，也没有凭空添加静态路由。若需要跨网段访问上游，请先配置正确的上级网关/路由。

启用后：

- LAN 到公网的 IPv4 TCP 透明走 SOCKS5。
- 私网/保留地址直连，内网 SOCKS5 上游也在绕过范围内。
- 默认不代理 UDP：公网 UDP 53（DNS）、123（NTP）直接放行，其他公网 UDP 拒绝，支持回退的 QUIC 应用可使用 TCP；依赖 UDP 的游戏/通话可能不可用。
- LAN 经路由器转发的 IPv6 被拒绝，防止绕过 IPv4 代理；不改变同一二层网络的 IPv6 行为。因此仅适用于路由器确实是流量出口的拓扑，不能控制旁路的其他网关。
- 路由器自身流量不代理；dnsmasq 继续使用 WAN 下发的 DNS。客户端应使用路由器作 DNS；默认并不保证 DNS 经 SOCKS5，如上级 DNS 无法解析目标域名，仍需另配可用 DNS。这不是完整 DNS 隧道方案。
- 不含按国家/域名分流、订阅和网页管理。

## 首次启用

代理默认关闭，便于先确认网络路由；没有在现有主机或路由器上自动部署。

通过 SSH 登录刷好固件的小米 mini，先设置管理密码、WAN 和 Wi-Fi；编辑 `/etc/hev-socks5-tproxy/main.yml`，将 `SOCKS_SERVER_ADDRESS` 和示例端口 `1080` 替换为真实参数。以下命令中的占位参数也需替换，随后检查上游路线：

```sh
SOCKS_IP='填写上游IP'
SOCKS_PORT='填写上游端口'
ip -4 route get "$SOCKS_IP"
nc -w 5 "$SOCKS_IP" "$SOCKS_PORT" </dev/null
```

nc 成功只说明端口可连接，不代表 SOCKS5 认证和出站转发成功。如需认证，在 /etc/hev-socks5-tproxy/main.yml 的 socks5 下增加 username 和 password；不要把真实凭据提交 GitHub。

启用并启动：

```sh
uci set lan-socks.main.enabled='1'
uci commit lan-socks
/etc/init.d/lan-socks restart
```

启动服务会加载 nft TPROXY 规则和策略路由；防火墙 reload 后也会重建。表 inet lan_socks、路由表 10010、策略规则优先级 10010、流量接管 mark 位 0x100、上游套接字 mark 位 0x200 为本方案预留，不要与其他策略路由插件混用。禁用流量卸载以避免绕过代理规则。

检查：

```sh
logread -e hev-socks5-tproxy
nft list table inet lan_socks
ip -4 rule show
ip -4 route show table 10010
```

从 LAN 设备测试网页并查看 nft 计数器和上游日志，确认真正经过代理。ping 不经过 SOCKS5，不能作为代理成功判据。

## 可选 UDP

只有确认上游支持并实际能转发标准 SOCKS5 UDP ASSOCIATE 时才启用：

```sh
uci set lan-socks.main.udp='1'
uci commit lan-socks
/etc/init.d/lan-socks restart
```

此时 LAN 到公网的 IPv4 UDP（含客户端直接查询公网 DNS）也被 TPROXY 接管；路由器自身 dnsmasq 的出站 DNS 仍直连。无需启用非标准 UDP-in-TCP 扩展。

## 停用与恢复直连

```sh
uci set lan-socks.main.enabled='0'
uci commit lan-socks
/etc/init.d/lan-socks stop
```

会移除本方案的 nft 表和专用策略路由，恢复原防火墙的转发行为（通常为直连）。进程单独崩溃而服务未停时，公网 TCP 仍被接管，不会自动切直连；procd 会尝试重启进程。

如果 LAN 桥名称不是 br-lan，请修改 /usr/libexec/lan-socks-rules 中两处 iifname 判断。不要开放 WAN 上的 1088 端口。

## 来源与许可

编译流程基于 [P3TERX/Actions-OpenWrt](https://github.com/P3TERX/Actions-OpenWrt)，沿用仓库 MIT 许可。代理核心为 [hev-socks5-tproxy](https://github.com/heiher/hev-socks5-tproxy)，固件源码为 [官方 OpenWrt](https://github.com/openwrt/openwrt)。
