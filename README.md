# 据实 · Countbook

**记账，不评判。** A ledger that does not editorialise.

据实 从不说「你花太多了」。它只说 **今日可用 −¥84.20**，然后让这个数字待在那里。

反乱花钱的机制不是提醒、不是奖励、不是评分弹窗，而是**对照你自己划下的标准，做诚实的记账**：

- 每一笔支出在花钱的当下被盖上 `必要 / 想要 / 冲动` 三枚印章之一 —— 强制，无默认值。
- 每一笔 `想要` 和 `冲动` 会在周日回来，由你自己给出 `值 / 不值` 的判决。
- 判为不值的金额累进成 **本年后悔** —— 永不清零，永不软化，结账后永不可静默修改。
- 还没发生的购买先进 **待购**，按价格比例冷静 1–14 天。唯一的摩擦被放在钱离开之前。

设计人格是彻底的克制：纸张、墨、发丝线、等宽数字。因为一个你无法反驳的数字，比任何警告横幅都更有矫正力。

| | |
|---|---|
| **网页版** | <https://chenzhiyuanthu.github.io/countbook/> — PWA，可安装，离线可用 |
| **iOS** | 原生 SwiftUI，`ios/`，用 Xcode 打开 `ios/Countbook.xcodeproj` 直接跑 |
| **多端同步** | 端到端加密。GitHub 私有仓库（无需服务器）或自建服务器 |

---

## 它算什么

每一个印在屏幕上的数字都有一条确定的公式，写在 [`docs/PRODUCT.md`](docs/PRODUCT.md) §5，实现在
[`web/src/core/compute.ts`](web/src/core/compute.ts)，由 iOS 端逐条对齐。

| | |
|---|---|
| **今日可用** | `(月度标准 − 本月已花 − 本月剩余固定支出) ÷ 剩余天数（含今天）`，整数分除法 |
| **小额漏水** | 低于 ¥30 的支出合并成一类，并换算成「≈ N 次大额支出」，除数是近 90 天大额支出的中位数 |
| **后悔账** | `Σ 判为不值的金额`，本月与本年两个数字；后悔率在满 30 笔判定前不显示 |
| **冷静期** | `clamp(⌈价格 ÷ ¥100⌉, 1, 14)` 天 —— 连续函数，没有 ¥999 与 ¥1,001 的悬崖 |
| **订阅侦测** | 同一商家、金额相差 ≤5%、出现 ≥3 次、到账间隔标准差 < 4 天；结果默认「待确认」，必须逐条 `保留` 或 `待退订` |
| **标准线** | 你自己设的月度与分类上限；一切报告都以「与标准的偏差」呈现，而非绝对值 |
| **连续天数** | 没有记录的一天会中断连胜 —— 否则「不记账」就是最优策略 |

## 它怎么存

账本是一条**只追加的事件日志**。没有任何东西被就地修改，任何两台设备只要看过同一批事件，
折叠出的账本就完全一致 —— 合并就是按 id 求并集、按混合逻辑时钟排序、然后 fold。

```
web/src/core/     领域逻辑，纯函数，35 项测试
  money.ts        Fen = 整数分，绝不出现浮点
  date.ts         Day = 'YYYY-MM-DD' 本地民用日期，23:40 的那笔属于当天
  hlc.ts          混合逻辑时钟：本机时钟被往回校正也不会乱序
  events.ts       事件并集 / 排序 / 压实
  fold.ts         事件 → 账本；删除优先于并发编辑，墓碑不复活
  compute.ts      上表的每一条公式
web/src/sync/     端到端加密与两种传输
  crypto.ts       CBK1 信封：PBKDF2-SHA256 600k → AES-256-GCM，整个包头是 AAD
  vault.ts        按月分片 + 比较并交换的同步循环
  github.ts       传输 A：私有仓库
  server.ts       传输 B：自建服务器
server/           可选的自建同步服务（Node 标准库 + SQLite，零依赖）
ios/              原生 SwiftUI，零第三方包
design/tokens.json 唯一的色值与度量真值，生成 CSS 变量与 Swift 主题
docs/             产品、设计系统、屏幕、协议四份规格（约 5,900 行）
```

## 同步与隐私

同步的两条通路共用同一套加密：**口令派生的密钥永远不离开你的设备**，
仓库或服务器拿到的只是 AES-256-GCM 密文。因此运营这台服务器 —— 包括 GitHub ——
不代表能读你的账本。

- **GitHub 私有仓库**（默认，不需要服务器）：数据是 `vault/s/<年-月>.cbk` 里的密文，
  用 blob SHA 做比较并交换。浏览器直连 `api.github.com`（它允许跨域与 Authorization 头）。
- **自建服务器**：`server/` 是一个只会按顺序追加密文的中继，用 Bearer 令牌鉴权
  （而不是 Cookie —— 网页版在 GitHub Pages 上跨域，第三方 Cookie 在 Safari 与 iOS 上会被丢弃）。

每台设备都会显示同一串**密钥指纹**（`4F2A · 91C7 · 0B3E · D845`）。对不上，就是口令不对。

口令丢了，账本就打不开了 —— 这是端到端加密的代价，没有后门可以绕过。

## 开发

```bash
npm install --prefix web
npm run --prefix web dev          # http://localhost:5173
npm run --prefix web test         # 领域逻辑与加密的测试
npm run --prefix web typecheck
node scripts/gen-tokens.mjs       # design/tokens.json → CSS 变量 + Swift 主题
python3 scripts/gen-icons.py      # 重新生成图标

./scripts/ios-check.sh            # 生成 Xcode 工程并编译到模拟器
./scripts/ios-check.sh test       # 跑 iOS 单元测试
open ios/Countbook.xcodeproj      # 或者直接在 Xcode 里跑
```

网页版推到 `main` 分支即自动部署到 GitHub Pages（`.github/workflows/pages.yml`）。

自建同步服务：

```bash
SSHPASS='...' ./server/deploy.sh                       # 默认 43.162.121.196
SSH_HOST=1.2.3.4 DOMAIN=count.example ./server/deploy.sh
```

脚本会自己判断这台机器上是否已经有别的 Caddy 占着 80/443：有就把 app 挂到同一个 docker
网络并打印要粘贴的站点块，没有就带上自己的 Caddy 一起起来。

## 明确的非目标

不接银行、不导入账单、不做记账社交、不做 AI 分类建议、不做「省钱攻略」推送、
不给你打分或发奖章。这些要么需要把你的流水交出去，要么把一个诚实的记录变成一个会讨好你的东西。
