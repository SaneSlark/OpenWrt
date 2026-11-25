# OpenWrt 固件更新日志

## 2026-11-25

- 合并三套构建的 MosDNS 兼容处理，移除重复的 LEDE 配置项和软件包下载步骤。
- 全新刷机时，全局网络选项的 IPv6 ULA 前缀默认留空。
- 标准 LAN 使用 `br-lan` 时，LuCI 网页终端默认绑定该设备。
- 修复 LEDE 和 ImmortalWrt 的 `opkg update`。运行时软件源不再列出仅供编译的第三方 feeds，LEDE 也排除 24.10.5 镜像站未提供索引的 `video` 源。

## 2026-11-24

- 三套固件启用 LAN IPv6 混合模式。上游提供前缀委派时分配子网，上游无委派时可中继 RA、DHCPv6 和 NDP。
- 修复官方版 LuCI 网络诊断漏查 `/usr/bin` 下的 IPv6 命令，构建时校验 IPv6 Ping 和 Traceroute。
- 三套固件恢复 HomeProxy 和简体中文界面，使用内置的 sing-box。
- 三套固件的 SSR-Plus 增加 Mihomo 1.19.34 后端。
- 三套固件均移除 Bypass 和 BypassCore，保留 OpenClash、PassWall 和 SSR-Plus。
- 修复官方 OpenWrt 镜像将编译用的第三方 feeds 写入 APK 官方源列表的问题，避免在 LuCI 中执行 `apk update` 时遇到无效索引。
- 新刷机时，DHCP 和 PPPoE 自动向上游请求 IPv6 前缀委派，默认关闭本地 ULA 前缀。LAN 继续从委派前缀分配 /64。
- Git tag 和 Release 标题统一使用北京时间，格式为 `方案名-YYYYMMDD-HHMMSS`。历史 Release 按原始发布时间更新。

## 2026-11-23

- 三套构建更新代理核心至 Xray 26.11.9、sing-box 1.14.4、Hysteria 2.14.0、TUIC Client 1.8.11 和 NaiveProxy 154.0.8037.49-5，并在发布前校验实际装入固件的版本。OpenClash 构建时继续获取上游最新稳定版 Mihomo。
- 三套固件统一纳入 ESXi 的 VMXNET3 网卡驱动。发布前检查各文件系统的 BIOS/UEFI 镜像是否成对、BIOS MBR 是否含引导代码，并核对 PPPoE、LuCI 常用应用和 TUN 等软件包是否实际进入固件。
- 三套固件用 `kinmeic/luci-app-bypass` v2.1.6 新架构替换 Nikki，内置 BypassCore v1.5.5、NaiveProxy 和 GeoIP/Geosite，并移除 Argon。
- 三套固件用 Nikki 替换 Clashoo，选用 Nikki 上游的稳定版 `mihomo-meta`，并新增 Argon `v3.1.4` 主题。
- 官方 OpenWrt 25.12.6 关闭 SSR-Plus 中依赖 `3proxy` 的可选 HTTP 代理组件，修复 `apk` 安装固件软件包时的缺包错误。配置校验会在编译前检查该依赖。

## 2026-11-22

### 新增

- 新增 `OpenWrt Official Build`，从官方 OpenWrt `v25.12.6` 源码构建 x86_64 固件，使用 `apk` 管理软件包。Actions 产物名称为 `OpenWrt_x86_64_Official`。
- 三套固件都加入 Vantage 主题和 Clashoo。可在 LuCI 的「语言和界面」切换主题。

### 兼容性与软件包

- 修正 Edge 登录页在新版 LuCI 上读取配置和加载脚本的方式，构建时校验所需的 Lua 运行库。
- 用 PassWall 替换 PassWall2，移除 HomeProxy、Samba 和 FTP 共享服务。
- LEDE 改用 firewall4 和 nftables，以支持 Clashoo，并匹配 PassWall 和 SSR-Plus 的透明代理配置。

### 构建与发布

- 补齐 Edge 登录模板兼容补丁中遗漏的空行，修复三套构建在预处理阶段中止的问题。
- 优先选用 PassWall 官方配方，解除 Clashoo 与 SSR-Plus 的软件包依赖循环，并启用官方 OpenWrt 的简体中文翻译选项。
- 推送到 `main` 后，LEDE、ImmortalWrt 和官方 OpenWrt 自动构建。编译和镜像校验通过后，Release 上传固件镜像和 `SHA256SUMS`。
- 移除手动补发旧构建的 `publish-existing.yml`。
