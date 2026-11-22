# OpenWrt 固件更新日志

## 2026-11-22

### 新增

- 新增 `OpenWrt Official Build`，从官方 OpenWrt `v25.12.6` 源码构建 x86_64 固件，使用 `apk` 管理软件包。Actions 产物名称为 `OpenWrt_x86_64_Official`。
- 三套固件都加入 Vantage 主题和 Clashoo。可在 LuCI 的「语言和界面」切换主题。

### 兼容性与软件包

- 修正 Edge 登录页在新版 LuCI 上读取配置和加载脚本的方式，构建时校验所需的 Lua 运行库。
- 用 PassWall 替换 PassWall2，移除 HomeProxy、Samba 和 FTP 共享服务。
- LEDE 改用 firewall4 和 nftables，以支持 Clashoo，并匹配 PassWall 和 SSR-Plus 的透明代理配置。

### 构建与发布

- 推送到 `main` 后，LEDE、ImmortalWrt 和官方 OpenWrt 自动构建。编译和镜像校验通过后，Release 上传固件镜像和 `SHA256SUMS`。
- 移除手动补发旧构建的 `publish-existing.yml`。
