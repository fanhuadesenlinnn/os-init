# ============================================================
# Mihomo / Clash Meta 订阅模板
# 场景：中国大陆日常使用 + 懒猫微服兼容 + 低维护
#
# 首次使用只需要修改 proxy-providers.airport.url。
# 不在模板中放示例节点，所有节点都从订阅链接拉取。
# ============================================================

# ------------------------------
# 基础监听
# ------------------------------
mixed-port: __MIHOMO_MIXED_PORT__
allow-lan: __MIHOMO_ALLOW_LAN__
bind-address: "__MIHOMO_BIND_ADDRESS__"
mode: rule
log-level: info
ipv6: true
unified-delay: true
tcp-concurrent: true

# 外部控制接口。建议仅本机访问；如需局域网访问，请务必设置 secret。
external-controller: __MIHOMO_CONTROLLER_HOST__:__MIHOMO_CONTROLLER_PORT__
# MetaCubeXD 安装后由 Mihomo 托管：http://127.0.0.1:9090/ui/
__METACUBEXD_EXTERNAL_UI_LINE__
# 如需局域网访问面板，请改为 0.0.0.0:9090，并务必设置 secret。
secret: __MIHOMO_SECRET_YAML__

profile:
  # 记住策略组选择，减少后续反复调整。
  store-selected: true
  # 记住 fake-ip 映射，重启后体验更稳定。
  store-fake-ip: true

# ------------------------------
# GEO 数据下载地址预留
# ------------------------------
# 默认不配置 geox-url，由 Mihomo 使用内置下载源。
# 如需固定 GeoIP / GeoSite / MMDB / ASN 下载地址，可在生成后的配置中手动添加。
# 这里保持原始直连，不叠加 GitHub 代理或规则代理。
# geox-url:
#   geoip: "https://..."
#   geosite: "https://..."
#   mmdb: "https://..."
#   asn: "https://..."

# ------------------------------
# TUN 透明代理
# ------------------------------
tun:
  # 桌面客户端一般可在 UI 里打开 TUN；服务端/路由器部署可改为 true。
  enable: false
  stack: mixed
  auto-route: true
  auto-detect-interface: true
  strict-route: true
  dns-hijack:
    - any:53
    - tcp://any:53
  # 懒猫微服要求：这两个地址必须绕过 TUN，确保打洞/局域网出口判断正常。
  route-exclude-address:
    - 6.6.6.6/32
    - 2000::6666/128

# ------------------------------
# DNS：大陆网络友好 + Fake-IP + 懒猫微服真实解析
# ------------------------------
dns:
  enable: true
  listen: __MIHOMO_DNS_LISTEN__
  ipv6: true
  cache-algorithm: arc
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  fake-ip-filter-mode: blacklist
  use-hosts: true
  use-system-hosts: true
  respect-rules: false

  # 用于解析 DNS 服务器域名，必须是 IP。
  default-nameserver:
    - 223.5.5.5
    - 119.29.29.29
    - 114.114.114.114

  # 国内 DNS 作为主解析，减少大陆服务延迟。
  nameserver:
    - https://dns.alidns.com/dns-query
    - https://doh.pub/dns-query
    - tls://223.5.5.5:853

  # 境外 DNS 仅在命中污染/境外规则时参与。
  fallback:
    - https://1.1.1.1/dns-query
    - https://8.8.8.8/dns-query
    - tls://1.0.0.1:853

  proxy-server-nameserver:
    - https://dns.alidns.com/dns-query
    - https://doh.pub/dns-query

  # DIRECT 出口使用独立 DNS，避免订阅直连下载时被复杂策略链影响。
  direct-nameserver:
    - 223.5.5.5
    - 119.29.29.29
    - https://dns.alidns.com/dns-query
    - https://doh.pub/dns-query
  direct-nameserver-follow-policy: false

  fallback-filter:
    geoip: true
    geoip-code: CN
    ipcidr:
      - 240.0.0.0/4
    domain:
      - +.google.com
      - +.facebook.com
      - +.youtube.com
      - +.twitter.com
      - +.x.com

  nameserver-policy:
    # 易污染/境外域名优先使用境外 DNS，替代旧版 fallback-filter.geosite。
    "geosite:gfw":
      - https://1.1.1.1/dns-query
      - https://8.8.8.8/dns-query
      - tls://1.0.0.1:853
    # 订阅 / 自建资源域名在启动期必须可直连解析，不能依赖动态规则。
    "+.babadafafafafa.cn":
      - 223.5.5.5
      - 119.29.29.29
      - https://dns.alidns.com/dns-query
      - https://doh.pub/dns-query
    # 懒猫微服要求：heiyu.space / lazycat.cloud 返回真实 IP，不能进入 fake-ip。
    "+.heiyu.space":
      - fc03:1136:3800::1
      - https://dns.alidns.com/dns-query
    "+.lazycat.cloud":
      - https://dns.alidns.com/dns-query
      - https://doh.pub/dns-query

  # 以下域名必须返回真实 IP，避免局域网、时间同步、投屏、游戏联机、懒猫微服异常。
  fake-ip-filter:
    - +.heiyu.space
    - +.lazycat.cloud
    - "*.lan"
    - "*.local"
    - "*.localdomain"
    - "*.home.arpa"
    - localhost
    - localhost.*.*
    - time.*.com
    - time.*.gov
    - time.*.edu.cn
    - time.*.apple.com
    - ntp.*.com
    - ntp.*.org
    - +.pool.ntp.org
    - +.msftconnecttest.com
    - +.msftncsi.com
    - stun.*.*
    - stun.*.*.*
    - +.stun.*.*
    - +.stun.*.*.*
    - +.stun.*.*.*.*
    - +.srv.nintendo.net
    - +.stun.playstation.net
    - xbox.*.microsoft.com
    - +.ipv6.microsoft.com
    - +.battlenet.com.cn
    - +.wotgame.cn
    - +.wggames.cn
    - +.wowsgame.cn
    - +.wargaming.net
    - music.163.com
    - "*.music.163.com"
    - "*.126.net"
    - "*.mcdn.bilivideo.cn"

# ------------------------------
# 嗅探：提升纯 IP、QUIC、部分客户端的分流准确度
# ------------------------------
sniffer:
  enable: true
  parse-pure-ip: true
  override-destination: true
  sniff:
    HTTP:
      ports: [80, 8080-8880]
      override-destination: true
    TLS:
      ports: [443, 8443]
    QUIC:
      ports: [443, 8443]
  force-domain:
    - +.v2ex.com
  skip-domain:
    - +.heiyu.space
    - +.lazycat.cloud
    - +.lan
    - +.local
    - Mijia Cloud

# ------------------------------
# 代理订阅：只保留一个机场示例
# ------------------------------
proxy-providers:
  airport:
    type: http
    # 只改这里：替换为你的机场订阅链接。不要把真实订阅链接提交到公开仓库。
    url: "https://example.com/your-subscription-url"
    interval: 86400
    path: ./providers/airport.yaml
    # 订阅拉取必须先于节点初始化，固定 DIRECT 避免落入 MATCH -> 节点选择。
    proxy: DIRECT
    health-check:
      enable: true
      interval: 600
      lazy: true
      url: https://www.gstatic.com/generate_204

# ------------------------------
# 策略组：不写示例节点，全部从 proxy-providers.airport 读取
# ------------------------------
proxy-groups:
  - name: 🚀 节点选择
    type: select
    proxies:
      - ♻️ 自动选择
      - 🛟 故障转移
      - 🚀 手动切换
      - DIRECT

  - name: 🚀 手动切换
    type: select
    use:
      - airport
    proxies:
      - DIRECT

  - name: ♻️ 自动选择
    type: url-test
    use:
      - airport
    url: https://www.gstatic.com/generate_204
    interval: 300
    tolerance: 50

  - name: 🛟 故障转移
    type: fallback
    use:
      - airport
    url: https://www.gstatic.com/generate_204
    interval: 300

  - name: 🤖 AI 服务
    type: select
    proxies:
      - 🚀 节点选择
      - 🚀 手动切换

  - name: 📺 流媒体
    type: select
    proxies:
      - 🚀 节点选择
      - 🚀 手动切换

  - name: 💬 Telegram
    type: select
    proxies:
      - 🚀 节点选择
      - 🚀 手动切换

  - name: 🧰 GitHub
    type: select
    proxies:
      - 🚀 节点选择
      - 🚀 手动切换
      - DIRECT

  - name: 🍎 Apple
    type: select
    proxies:
      - DIRECT
      - 🚀 节点选择

  - name: Ⓜ️ Microsoft
    type: select
    proxies:
      - DIRECT
      - 🚀 节点选择

  - name: 🎮 游戏平台
    type: select
    proxies:
      - DIRECT
      - 🚀 节点选择

  - name: 🎯 国内流量
    type: select
    proxies:
      - DIRECT
      - 🚀 节点选择

  - name: 🛑 广告拦截
    type: select
    proxies:
      - REJECT
      - DIRECT

  - name: 🐱 懒猫微服
    type: select
    proxies:
      - DIRECT

# ------------------------------
# 分流规则：从高优先级到低优先级
# ------------------------------
rules:
  # 启动期基础资源先静态直连，不依赖尚未下载完成的 rule-providers。
  - DOMAIN-SUFFIX,babadafafafafa.cn,DIRECT

  # 懒猫微服：官方要求真实 DNS、TUN 旁路、IPv6 内网段直连。
  - DOMAIN-SUFFIX,heiyu.space,🐱 懒猫微服
  - DOMAIN-SUFFIX,lazycat.cloud,🐱 懒猫微服
  - IP-CIDR,6.6.6.6/32,DIRECT,no-resolve
  - IP-CIDR6,2000::6666/128,DIRECT,no-resolve
  - IP-CIDR6,fc03:1136:3800::/40,DIRECT,no-resolve

  # 本机、局域网、链路本地地址先静态直连，避免依赖外部 private/lancidr 规则。
  - DOMAIN-SUFFIX,lan,DIRECT
  - DOMAIN-SUFFIX,local,DIRECT
  - IP-CIDR,127.0.0.0/8,DIRECT,no-resolve
  - IP-CIDR,10.0.0.0/8,DIRECT,no-resolve
  - IP-CIDR,172.16.0.0/12,DIRECT,no-resolve
  - IP-CIDR,192.168.0.0/16,DIRECT,no-resolve
  - IP-CIDR,169.254.0.0/16,DIRECT,no-resolve
  - IP-CIDR6,::1/128,DIRECT,no-resolve
  - IP-CIDR6,fc00::/7,DIRECT,no-resolve
  - IP-CIDR6,fe80::/10,DIRECT,no-resolve

  # 局域网、私有地址、系统服务永远直连。
  - RULE-SET,private,DIRECT
  - RULE-SET,lancidr,DIRECT,no-resolve
  - RULE-SET,applications,DIRECT

  # 广告与 HTTPDNS。HTTPDNS 走拦截可减少 App 绕过系统 DNS。
  - RULE-SET,reject,🛑 广告拦截
  - RULE-SET,httpdns,🛑 广告拦截

  # 常见服务分组。
  - RULE-SET,ai,🤖 AI 服务
  - RULE-SET,youtube,📺 流媒体
  - RULE-SET,netflix,📺 流媒体
  - RULE-SET,disney,📺 流媒体
  - RULE-SET,spotify,📺 流媒体
  - RULE-SET,telegram,💬 Telegram
  - RULE-SET,telegramcidr,💬 Telegram,no-resolve
  - RULE-SET,github,🧰 GitHub
  - RULE-SET,apple,🍎 Apple
  - RULE-SET,icloud,🍎 Apple
  - RULE-SET,microsoft,Ⓜ️ Microsoft
  - RULE-SET,steam,🎮 游戏平台

  # 国内域名/IP 直连，国外常见规则走代理。
  - RULE-SET,direct,🎯 国内流量
  - RULE-SET,cncidr,🎯 国内流量,no-resolve
  - RULE-SET,proxy,🚀 节点选择
  - RULE-SET,gfw,🚀 节点选择
  - RULE-SET,greatfire,🚀 节点选择
  - RULE-SET,tld-not-cn,🚀 节点选择
  - GEOIP,CN,🎯 国内流量
  - MATCH,🚀 节点选择

# ------------------------------
# 规则提供者：自动更新，后续维护成本低
# ------------------------------
rule-providers:
  reject:
    type: http
    behavior: domain
    url: https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/reject.txt
    path: ./ruleset/reject.yaml
    interval: 86400

  private:
    type: http
    behavior: domain
    url: https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/private.txt
    path: ./ruleset/private.yaml
    interval: 86400

  direct:
    type: http
    behavior: domain
    url: https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/direct.txt
    path: ./ruleset/direct.yaml
    interval: 86400

  proxy:
    type: http
    behavior: domain
    url: https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/proxy.txt
    path: ./ruleset/proxy.yaml
    interval: 86400

  gfw:
    type: http
    behavior: domain
    url: https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/gfw.txt
    path: ./ruleset/gfw.yaml
    interval: 86400

  greatfire:
    type: http
    behavior: domain
    url: https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/greatfire.txt
    path: ./ruleset/greatfire.yaml
    interval: 86400

  tld-not-cn:
    type: http
    behavior: domain
    url: https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/tld-not-cn.txt
    path: ./ruleset/tld-not-cn.yaml
    interval: 86400

  telegramcidr:
    type: http
    behavior: ipcidr
    url: https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/telegramcidr.txt
    path: ./ruleset/telegramcidr.yaml
    interval: 86400

  cncidr:
    type: http
    behavior: ipcidr
    url: https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/cncidr.txt
    path: ./ruleset/cncidr.yaml
    interval: 86400

  lancidr:
    type: http
    behavior: ipcidr
    url: https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/lancidr.txt
    path: ./ruleset/lancidr.yaml
    interval: 86400

  applications:
    type: http
    behavior: classical
    url: https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/applications.txt
    path: ./ruleset/applications.yaml
    interval: 86400

  icloud:
    type: http
    behavior: domain
    url: https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/icloud.txt
    path: ./ruleset/icloud.yaml
    interval: 86400

  apple:
    type: http
    behavior: domain
    url: https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/apple.txt
    path: ./ruleset/apple.yaml
    interval: 86400

  httpdns:
    type: http
    behavior: classical
    url: https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/BlockHttpDNS/BlockHttpDNS.yaml
    path: ./ruleset/block-httpdns.yaml
    interval: 86400

  ai:
    type: http
    behavior: classical
    url: https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/OpenAI/OpenAI.yaml
    path: ./ruleset/ai.yaml
    interval: 86400

  youtube:
    type: http
    behavior: classical
    url: https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/YouTube/YouTube.yaml
    path: ./ruleset/youtube.yaml
    interval: 86400

  netflix:
    type: http
    behavior: classical
    url: https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/Netflix/Netflix.yaml
    path: ./ruleset/netflix.yaml
    interval: 86400

  disney:
    type: http
    behavior: classical
    url: https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/Disney/Disney.yaml
    path: ./ruleset/disney.yaml
    interval: 86400

  spotify:
    type: http
    behavior: classical
    url: https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/Spotify/Spotify.yaml
    path: ./ruleset/spotify.yaml
    interval: 86400

  telegram:
    type: http
    behavior: classical
    url: https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/Telegram/Telegram.yaml
    path: ./ruleset/telegram.yaml
    interval: 86400

  github:
    type: http
    behavior: classical
    url: https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/GitHub/GitHub.yaml
    path: ./ruleset/github.yaml
    interval: 86400

  microsoft:
    type: http
    behavior: classical
    url: https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/Microsoft/Microsoft.yaml
    path: ./ruleset/microsoft.yaml
    interval: 86400

  steam:
    type: http
    behavior: classical
    url: https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/Steam/Steam.yaml
    path: ./ruleset/steam.yaml
    interval: 86400
