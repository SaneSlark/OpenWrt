# GitHub 自动编译 OpenWrt

这是一个基于 GitHub Actions 的 OpenWrt 自动编译框架，用来集中管理编译配置、自定义脚本和固件产物。

当前仓库保留两套 x86_64 构建方案：

- `OpenWrt lede Build`：基于 `coolsnowwolf/lede`，优先保证经典 LEDE 固件稳定产出。
- `OpenWrt Immortal Build`：基于 `immortalwrt/immortalwrt`，用于较新的代理插件和最新固件。

## 目录结构

```text
.
|-- .github/workflows/build-lede.yml
|-- .github/workflows/build-immortal.yml
|-- config/
|   |-- lede_x86_64.config
|   `-- immortal_x86_64.config
`-- scripts/
    |-- diy-lede.sh
    `-- diy-immortal.sh
```

## 使用方法

1. 将当前仓库推送到 GitHub。
2. 打开仓库的 `Actions` 页面。
3. 根据需要运行 `OpenWrt lede Build` 或 `OpenWrt Immortal Build`。
4. 按需填写以下参数：
   - `repo_url`：OpenWrt 源码仓库地址
   - `repo_branch`：源码分支
   - `config_file`：当前仓库中的配置文件路径
   - `script_file`：当前仓库中的自定义脚本路径
   - `artifact_name`：上传后的产物名称
   - `compile_threads`：编译线程数，`0` 表示自动使用全部 CPU
   - `upload_release`：是否同时创建 GitHub Release

## 默认入口

LEDE 构建：

- 默认源码：`https://github.com/coolsnowwolf/lede`
- 默认分支：`master`
- 默认配置：`config/lede_x86_64.config`
- 默认脚本：`scripts/diy-lede.sh`

ImmortalWrt 构建：

- 默认源码：`https://github.com/immortalwrt/immortalwrt`
- 默认分支：`openwrt-24.10`（保留此前因主题兼容而回退的版本基础，每次构建拉取该分支最新代码）
- 默认配置：`config/immortal_x86_64.config`
- 默认脚本：`scripts/diy-immortal.sh`

两个脚本都支持两个执行阶段：

- `STAGE=pre`：添加 feeds、主题和额外插件
- `STAGE=post`：在复制 `.config` 之后修改默认配置

## 主题与插件说明

LEDE 方案默认启用 `luci-theme-edge`、常用 LuCI 应用、`OpenClash`、`SSR-Plus`、`PassWall2` 和基础命令行工具。

ImmortalWrt 方案默认启用 `luci-theme-edge`、`OpenClash`、`SSR-Plus`、`PassWall2` 和 `HomeProxy`。

OpenClash 从 `vernesong/OpenClash` 的 `master` 获取最新源码；PassWall2 及其依赖从官方 `Openwrt-Passwall` 的 `main` 获取。代理核心使用上游软件包定义，不再覆盖为旧版 Xray/Hysteria 二进制。OpenClash 额外内置最新稳定版 Mihomo 的 amd64-compatible 核心，下载时验证 GitHub 发布资产的 SHA256；下载或校验失败会终止构建。

两套配置均包含：

- 基本路由、NAT、防火墙、LuCI 网络管理、DHCP 上网和 PPPoE 拨号。
- IPv6 内核、DHCPv6 客户端、前缀委派（PD）、odhcpd 的 DHCPv6 服务、RA 与 SLAAC。
- dnsmasq-full：DNS 缓存、DHCPv4、静态租约、DNSSEC 和 IPv6 DNS 解析支持；IPv6 地址分配由 odhcpd 负责。
- LEDE 使用 firewall3/iptables/ipset，ImmortalWrt 使用 firewall4/nftables/nftset，PassWall2 的透明代理后端与之匹配。

首次应用网络默认配置时，LAN 为 `192.168.2.1/24`，DHCP 地址池为 `.100` 至 `.249`、租期 12 小时，LAN 分配 IPv6 /64 并启用 RA/SLAAC 与 DHCPv6；DHCP WAN 自动请求 IPv6 地址和前缀，不屏蔽 AAAA。公网 IPv6 仍需运营商提供地址及 PD；PPPoE 账号和密码需在刷机后填写。保留旧配置升级时请检查现有网络设置，完整默认配置以全新刷写为准。

OpenClash 和 PassWall2 默认关闭，导入订阅后选择一个启用。同一网络不要同时启用多个透明代理或 DNS 接管服务，以免争抢规则和端口。其他已有代理插件也应保持关闭。

优先使用 `OpenWrt Immortal Build` 构建 24.10 固件。此前因为兼容问题回退过版本，因此保留 ImmortalWrt `openwrt-24.10` 和 LEDE 的 LuCI `openwrt-24.10` 分支，不自动升级到 25.12；LEDE 主源码仍跟随原来的 `master`，所以新内核与旧 LuCI 的组合也需要编译和实机验证。Edge 使用 `master` 分支的 Lua 模板，显式包含 `luci-compat`、`luci-lua-runtime`，同时保留 Bootstrap 备用主题。兼容库齐全不代表页面已通过实测。

构建产物附带 `build.config`、`feeds.conf.default`、`source-versions.txt` 和 `openclash-core-version.txt`，方便核对实际源码和核心版本。此仓库保存构建配置，完整 OpenWrt 源码由 Actions 在构建时克隆。

工作流在 `make defconfig` 后检查必需配置；编译后检查 BIOS/UEFI 镜像是否存在、gzip 是否完整，以及实际固件 manifest 是否包含路由、IPv6、DNS/DHCP、OpenClash、PassWall2 和核心组件。上传时附带 manifest 与 `SHA256SUMS`。这些检查不代替实机测试：验收还需要确认 WAN 上网、LAN DHCP/静态租约、IPv4 NAT、IPv6 PD/RA/DHCPv6、AAAA 解析、防火墙和两个代理分别运行。构建失败会保留诊断日志；只有 Actions 实际编译通过才表示已成功产出固件。

默认情况下，两个方案都会把 LAN IP 改为 `192.168.2.1`，将 LuCI 默认语言设置为简体中文，并将默认主题设置为 `edge`。

## 已包含功能

- 支持手动触发编译
- LEDE workflow 支持 `repository_dispatch` 触发
- 支持 `dl` 和 `ccache` 缓存
- 自动上传编译产物
- 可选自动创建 GitHub Release
- 支持通过脚本切换主题和常用插件

## 扩展建议

- 新增机型时，可以在 `config/` 下添加新的 `.config` 文件。
- 切换源码仓库或分支时，可以直接在工作流输入参数中修改。
- 如果后续需要多机型并行编译，可以继续扩展 matrix 构建。
