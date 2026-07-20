---
layout: mypost
title: HTTP/2 Bomb：HPACK 索引引用放大链攻击技术深度剖析
author: minc_nice_100
category: "论文"
description: 深入剖析 HTTP/2 Bomb 攻击原理:HPACK 索引引用放大链与流控窗口卡死组合,实现高达 5700:1 的流量放大,覆盖 nginx、Envoy、IIS 等主流实现。
---

> 本文由 Deepseek V4 Pro 撰写(太累了不想写了), 还没审校, 还请各位读者帮我排排错, 原论文在文末
>

---

## 1. 引言

2026 年 6 月 2 日，Calif Security Research 披露了一个名为 **HTTP/2 Bomb** 的远程拒绝服务漏洞。受影响的是五个主流 HTTP/2 服务器实现的全线默认配置：**nginx、Apache httpd、Microsoft IIS、Envoy Proxy、Cloudflare Pingora**。

这个攻击的核心思路极其简洁：

> 把 HPACK 索引引用炸弹 + HTTP/2 流控窗口卡死，组合成一条 TCP 连接。

放大比从 68:1 到 5,700:1 不等。最严重的情况下，单个 100 Mbps 攻击机在约 10 秒内就能耗尽 32 GB 服务器内存。

**本文的主要贡献：**

1. 协议层面完整还原攻击机制，包括精确的 HPACK 编码和流控卡死时序
2. 逐一分析五个实现的源码级修复方案
3. 梳理 2016—2026 十年间该漏洞类别的 CVE 演化谱系
4. 指出 RFC 7541 §7.3 的根本性规范缺陷
5. 提出通用的 HTTP/2 防御模型

---

## 2. 背景：HPACK 与 HTTP/2 流控

### 2.1 HPACK 头部压缩

HPACK（RFC 7541）是一种有状态的头部压缩方案，使用两张查找表：

- **静态表**（索引 1–61）：预定义的常见头部字段
- **动态表**（索引 62 起）：在连接生命周期中累积的头部名值对

发送方可以使用四种表示之一：

1. **索引头部字段**（`0x80 | index`）：单字节引用已有表项，最紧凑
2. **增量索引字面量**（`0x40 | ...`）：字面发送，加入动态表
3. **不索引字面量**（`0x00 | ...`）：字面发送，不加入表
4. **永不索引字面量**（`0x10 | ...`）：字面发送，显式排除（如敏感头部）

动态表按 FIFO 顺序维护。当新条目会使表大小超过 `SETTINGS_HEADER_TABLE_SIZE`（默认 4096 字节）时，最旧的条目被驱逐。编码器对索引和驱逐有完全控制权。

### 2.2 HTTP/2 流控

HTTP/2 实现基于信用的流控机制，分两级：每流和每连接（RFC 9113 §5.2）。接收方通告一个窗口大小，发送方不得超出该窗口发送 DATA 帧。新流的初始窗口大小默认为 65,535 字节，可通过 `SETTINGS_INITIAL_WINDOW_SIZE` 参数修改。

**关键点：** 客户端和服务器各自独立控制接收窗口。客户端将 `SETTINGS_INITIAL_WINDOW_SIZE = 0` 时，等于告诉服务器"我一字节 DATA 都不能收"。

窗口恢复通过 `WINDOW_UPDATE` 帧（type 0x8）实现，其载荷为一个 31 位无符号整数，表示发送方可额外发送的字节数。

---

## 3. 攻击机制

HTTP/2 Bomb 在单条多路复用 HTTP/2 连接上串联两个原语：

**第一阶段：HPACK 索引引用炸弹** — 通过发送数千个单字节 HPACK 索引引用，迫使服务器为每个引用分配完整的 per-entry 内存结构。

**第二阶段：流控窗口卡死** — 通过通告零字节流控窗口并定期滴入 1 字节 `WINDOW_UPDATE` 帧来重置超时计时器，阻止服务器完成响应（从而永不释放已分配的内存）。

### 3.1 第一阶段：HPACK 索引引用炸弹

**步骤 A：播种动态表**

```
0x40 0x06 "x-bomb" 0x00
```

这是一个增量索引字面量：头部名 `x-bomb`（6 字节），空值（0 字节）。条目被添加到动态表索引 62。线路成本：9 字节。服务器成本：约 38–59 字节（取决于实现）。

**步骤 B：发送数千个索引引用**

```
0xBE × N    （0xBE = 0x80 | 62）
```

每个 `0xBE` 字节是对动态表条目 62 的索引头部字段引用。线路上：1 字节。服务器端：必须查找条目并构造完整的头部结构。Calif 的测量显示，在 nginx 上每个引用消耗约 59 字节 pool 内存——3 字节在 `state.pool`，56 字节在 `ngx_table_elt_t` 结构体中。

### 3.2 为什么现有防御失效

区分 HTTP/2 Bomb 与其前身的关键洞察在于**放大来源**。

经典 HPACK Bomb（CVE-2016-6581）用等于最大表大小的头部值填满动态表，然后反复引用，实现 4,096:1 或更高的压缩比。服务器学会了通过限制**解码后头部总大小**来防御。

HTTP/2 Bomb 反其道而行：头部值几乎是空的（`""`）。解码大小限制永远不会触发，因为几乎没有什么需要解码。放大来自服务器围绕每个引用分配的**per-entry 簿记开销**——pool block、结构体开销、内部元数据——无论值大小，这些都会存在。

### 3.3 Cookie 碎屑绕过（Apache 和 Envoy）

对于同时（或仅）执行头部**字段数量**限制的服务器，攻击者还有第二种绕过手段。

RFC 9113 §8.2.3 明确允许将 `Cookie` 头部分割为多个独立字段（称为"碎屑"crumbs），以提高 HPACK 压缩效率。服务器在转发给后端之前，应将碎屑重新组装为单个 HTTP/1.1 兼容的 `Cookie` 头部。

漏洞的根源在于：Apache 的 `mod_http2` 和 Envoy 的 HTTP/2 编解码器都没有将 cookie 碎屑计入字段数量限制。Apache 中，每个碎屑被排除在 `LimitRequestFields` 计数之外；Envoy 中，`max_request_headers_kb` 检查在 cookie 合并之前完成。攻击者因此可以发送数千个独立的 cookie 碎屑，每个都是一个 HPACK 索引引用，同时躲过大小限制和数量限制。

#### Envoy 的放大路径

Envoy 将每个到达的 cookie 碎屑追加到不断增长的缓冲区中。分配器开销随每次追加而叠加，在单个流上实测放大比约 **5,700:1**。关键问题是 Envoy 在合并 cookie 碎片**之前**验证 `max_request_headers_kb`——32,768 个碎屑合并后的 cookie 总量可达 126.9 MiB，完全绕过了大小检查。

#### Apache httpd 的放大路径

Apache 的 `mod_http2` 由于 cookie 合并实现的问题，内存消耗更为激进。函数 `h2_req_add_header()` 为每个到达的碎屑调用 `apr_psprintf(pool, "%s; %.*s", existing, ...)`，每次都分配一个新的 APR pool 字符串，拼接之前的结果。更糟糕的是，旧的中间字符串由于 APR 的 pool 式内存管理设计，直到流清理时才被释放。这产生了**平方级内存增长**：

$$ \text{Memory} = \sum_{i=1}^{N} (2i + 1) \approx O(N^2) $$

仅 4,091 个空 cookie 碎屑，**最终**合并后的 cookie 值只有 8,182 字节（完全在默认 `LimitRequestFieldSize` 8,190 字节以内），但累积的中间 pool 分配消耗了约 16 MB per stream。每条连接 100 个并发流，超过 1.5 GB。

**各实现放大特性汇总：**

| 实现 | 放大比 | 耗尽 32 GB 时间 | 攻击向量 |
|---|---|---|---|
| Envoy 1.37.2 | ~5,700:1 | ~10 秒 | Cookie 碎屑 + 缓冲区追加 + 分配器 |
| Apache httpd 2.4.67 | ~4,000:1 | ~18 秒 | Cookie 碎屑 + 平方级字符串重建 |
| nginx 1.29.7 | ~70:1 | ~45 秒 | 纯簿记开销（`ngx_table_elt_t`） |
| Microsoft IIS | ~68:1 | ~45 秒 | 纯簿记开销 |
| Cloudflare Pingora | ~68:1 | — | 纯簿记开销 |

### 3.4 第二阶段：流控窗口卡死

第一阶段实现大量内存分配。第二阶段阻止内存被释放。精确的 HTTP/2 帧序列：

```
Client -> Server:
  PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n          (连接前导)
  SETTINGS [INITIAL_WINDOW_SIZE=0]           (卡死：不允许任何响应)
  SETTINGS ACK                               (确认服务器的 SETTINGS)
  HEADERS [stream 1] <- 炸弹载荷             (伪头部 + HPACK 炸弹)
  HEADERS [stream 3] <- 炸弹载荷
  HEADERS [stream 5] <- 炸弹载荷
  ...
  WINDOW_UPDATE(1) per stream / 1 秒         (保活：重置 send_timeout)
```

关键要素：

- **`SETTINGS_INITIAL_WINDOW_SIZE = 0`**：服务器处理 `HEADERS` 帧，分配炸弹触发的所有内存，但无法发送任何 DATA 响应
- 服务器的发送超时在正常情况下会关闭连接并释放内存。攻击者通过大约每秒发送 1 字节 `WINDOW_UPDATE` 来重置服务器的内部计时器，而不真正推进流控窗口
- 攻击在 HTTP 访问日志中完全不可见，因为服务器从未完成请求处理，不写入日志

### 3.5 为什么组合是协同放大的

单独来看，两个原语都不致命。HPACK 放大产生大量内存分配，但这些分配通常在毫秒级内被释放。流控卡死可以保持资源占用，但每个被卡死的流的基础内存通常只有几 KB。组合产生了乘法效应：高放大比的内存膨胀被固定在攻击者控制的时间窗口内。

---

## 4. 协议规范缺陷

RFC 7541 §7.3 标题为"Memory Consumption"（内存消耗），开篇警告"攻击者可能试图导致端点耗尽内存"，随后解释 HPACK 通过 `SETTINGS_HEADER_TABLE_SIZE` 限制了动态表，结论是该问题已处理。

**五个独立的实现团队都读了这一节，然后写出了同一类漏洞。** 我们识别出两个明确的规范缺陷：

### 缺陷一：放大比作为不充分的威胁模型

规范纯粹以**压缩比**来框定内存风险——即线路字节与解压输出字节之间的关系。但 HTTP/2 Bomb 证明，压缩比只是等式的一半。70:1 的放大器在请求完成即释放内存时无害；当协议允许客户端几乎零成本地保持连接打开、将每个已分配的字节固定在攻击者控制的时间窗口内时，它就变成了毁灭性攻击。

### 缺陷二：Per-Entry 分配器开销不可见

规范将 `SETTINGS_HEADER_TABLE_SIZE` 视为 HPACK 相关内存消耗的充分界限。然而，这个设置仅控制**压缩状态**——即动态表本身。它并不约束服务器在处理解码后的头部列表时创建的临时分配。per-entry 簿记开销——pool block、`ngx_table_elt_t` 结构体、零终止拷贝——完全不在规范的内存模型内。

---

## 5. 各实现修复分析

### 5.1 nginx — 1.29.8

- **Commit:** `3656941`（Maxim Dounin，2026 年 4 月 7 日）
- **来源：** 从 freenginx changeset `199dc0d6b05b`（2024 年 5 月 24 日）导入
- **未分配独立 CVE**

修复引入新的 `max_headers` 配置指令，默认限制为每请求 1,000 个头部。涉及三个源文件：

- `src/http/ngx_http_core_module.c`：声明参数，初始化为 `NGX_CONF_UNSET_UINT`，合并默认值 `1000`
- `src/http/ngx_http_request.c`：HTTP/1 请求解析器中，在每个头部行之后递增计数器，超过限制时返回 HTTP 431
- `src/http/v2/ngx_http_v2.c`：在 HTTP/2 路径中推送解析头部到 `r->headers_in.headers` 之前应用相同检查

关键代码逻辑：

```c
if (r->headers_in.count++ >= cscf->max_headers) {
    r->close = 1;
    ngx_log_error(NGX_LOG_INFO, c->log, ...);
    ngx_http_finalize_request(r, NGX_HTTP_REQUEST_HEADER_TOO_LARGE);
}
```

计数器在 `ngx_list_push()` 调用**之前**递增，确保一旦达到限制就阻止分配发生。

**值得注意：** Ubuntu 安全团队报告该修复"破坏了 ABI 并引入了导致 nginx 在使用外部模块时崩溃的回归。CVE 修复在 8398-2 中被回退，等待进一步调查。"

### 5.2 Apache httpd — CVE-2026-49975

- **Commit:** `47d3100b`（Stefan Eissing，2026 年 5 月 27 日）
- **影响版本：** 2.4.17 至 2.4.67
- **修复版本：** mod_http2 v2.0.41，Apache 2.4.68
- **CVSSv4:** 8.7（HIGH）

Apache 的修复包含三个并发变更：

1. **重复头部现计入 `LimitRequestFields`。** 此前，`apr_table_mergen` 在计数时将重复的空头部折叠为单个逻辑条目，而内存池为每次出现分配存储。修复使计数反映实际分配次数。
2. **零终止拷贝移至连接级临时缓冲区。** 不再为每次头部名/值拷贝分配新的 pool 字符串，而是使用连接级持有的单个可重用缓冲区，消除了作为主要放大向量的 per-allocation 开销。
3. **HTTP/2 请求池系统内存在请求结束时归还。** 此前，APR pool 的设计（`apr_pool_clear()` 保留内存供重用）允许分配在 HTTP/2 连接上的多个请求之间持续存在。修复强制在请求完成时归还系统内存。

**部分缓解说明：** 降低 `LimitRequestFieldSize` 可以减少单流爆炸半径（它限制了合并后的 cookie，从而限制了碎屑数量），但攻击者仍可在多流和多连接上放大效果。单独降低 `LimitRequestFields` 无效，因为重复的 cookie 碎屑不计入其中。

### 5.3 Envoy — CVE-2026-47774（GHSA-22m2-hvr2-xqc8）

- **修复版本：** 1.35.11, 1.36.7, 1.37.3, 1.38.1（2026 年 6 月 3 日）
- **影响：** 1.39 之前的所有版本
- **CVSSv4:** 7.5（HIGH）

Envoy 的公告指出必须同时解决两个相互作用的弱点：

**修复一 — 头部大小验证中的 Cookie 字节核算。** 在处理 HTTP/2 请求时，cookie 头部碎片被单独缓冲，仅在请求头部大小验证**之后**合并。合并后的 cookie 总量不受 `max_request_headers_kb` 约束。修复确保缓冲的 cookie 字节在请求接受前被纳入请求头部大小核算。

**修复二 — 解码后头部大小限制。** 内部 `oghttp2/quiche` 编解码器仅对**编码后**的 HPACK 字节执行头部块限制，没有对应的**解码后**头部总大小限制。攻击者可使用动态表引用保持编码表示较小（36,844 字节），而解码后的 cookie 值扩展到 133 MB。修复在编码块大小之外，额外强制执行解码后头部大小限制。

公告明确指出："**完整修复需要同时解决两个因素。只修复一侧可能降低可利用性，但无法完全解决底层问题。**"

**后续版本**（v1.35.12, 1.36.8, 1.37.4, 1.38.2，约 2026 年 6 月 10 日）：增加了可观测性 instrumentation——`header_count`、`header_list_size`、`cookie_count` 和 `cookie_size` 的直方图——以及专用的 `http2_max_cookies_size_in_kb` 运行时配置。

### 5.4 Microsoft IIS — CVE-2026-49160

Microsoft 通过 2026 年 6 月 10 日的 Patch Tuesday 发布解决了该漏洞。具体修复机制未公开详细文档，但据了解遵循了强制执行独立于解码大小的头部字段数量限制的通用模式。

### 5.5 H2O — GHSA-qcrr-wrhc-pgq9

- **Commit:** `9265bdd`（Kazuho Oku，2026 年 6 月 3 日）

H2O 实现了双重限制策略：

- `H2O_HPACK_MAX_HEADERS_HARD_LIMIT = 1000`：超出立即关闭连接
- `H2O_MAX_HEADERS = 100`：超出返回 HTTP 400

H2O 已经在内部尽可能以引用方式表示 HTTP 头部名值，从设计上减少了 HPACK 状态放大。新的限制为解码后的头部状态提供了显式边界。

### 5.6 HAProxy — 架构性免疫

HAProxy 的 HTTP/2 实现不受 HTTP/2 Bomb 攻击影响。其核心设计以严格的固定大小内存约束处理 HTTP/2 流，以线速处理帧，不累积动态分配。单个连接和流的内存占用在设计上就有界，防止了此类攻击所特有的无界消耗。

---

## 6. 历史 CVE 谱系

下图追溯了该漏洞类别的演化。两条独立的攻击路线——HPACK 压缩放大（左列）和流控/资源耗尽（右列）——从 2016 年起并行演化，最终在 2026 年被组合为单条攻击链。

```
  左列 (HPACK 压缩放大)              右列 (流控/资源耗尽)
  ┌──────────────────────┐          ┌──────────────────────┐
  │ CVE-2016-6581        │          │ CVE-2016-8740        │
  │ (Benfield, 2016)     │          │ (Apache, 2016)       │
  │ "HPACK Bomb"         │          │ 无界 CONTINUATION 帧  │
  │ 4,096:1 压缩比       │          └──────────┬───────────┘
  └──────────┬───────────┘                     │
             │                                 ▼
             │                    ┌──────────────────────┐
             │                    │ CVE-2023-44487       │
             │                    │ (Google, 2023)       │
             │                    │ HTTP/2 Rapid Reset   │
             │                    │ 大规模流取消耗尽      │
             │                    └──────────┬───────────┘
             │                               │
             ▼                               ▼
  ┌──────────────────────┐      ┌──────────────────────┐
  │ CVE-2025-53020       │      │ CVE-2023-43622       │
  │ (Bar Nahum, 2025)    │      │ (Apache, 2023)       │
  │ Apache HPACK         │      │ Window=0 无限连接阻塞 │
  │ 4,000:1 放大         │      └──────────┬───────────┘
  └──────────┬───────────┘                 │
             │          ╲  组合  ╱          │
             │           ╲     ╱           │
             ▼            ╲   ╱            ▼
  ┌──────────────────────┐  ╲╱  ┌──────────────────────┐
  │ CVE-2026-49975       │  ╱╲  │ CVE-2026-47774       │
  │ (Calif/Codex, 2026)  │ ╱  ╲ │ (Calif/Codex, 2026)  │
  │ HTTP/2 Bomb          │╱    ╲│ HTTP/2 Bomb          │
  │ Apache: cookie 碎屑  │       │ Envoy: 编解码绕过    │
  │ + 平方级字符串重建   │       │ + cookie 核算绕过    │
  └──────────────────────┘       │ 5,700:1 放大         │
                                 └──────────────────────┘
```

- HPACK 压缩放大路线：原始 HPACK Bomb（CVE-2016-6581）→ Gal Bar Nahum 在 Apache 上独立重新发现（CVE-2025-53020）
- 流控/资源耗尽路线：无界 CONTINUATION 帧（CVE-2016-8740）→ 跨实现的 Rapid Reset 攻击（CVE-2023-44487）→ 显式零窗口连接阻塞（CVE-2023-43622）
- 两条路线汇聚于 2026 年协调披露：CVE-2026-49975（Apache）和 CVE-2026-47774（Envoy），是同一次研究的并行发现

Codex 识别到的关键洞察是这两条路线可以被**组合**——第一条路线的内存放大可以被第二条路线的卡死机制**固定**。正如 Calif 的披露中所说："这个组合一旦看到就显而易见，但据我们所知，在此之前没有人将它们拼在一起对付这些服务器。"

---

## 7. 通用防御模型

从攻击机制和厂商修复的分析中，我们推导出 HTTP/2 终止点的通用防御模型。核心原则是：

> **"最大解码头部大小"和"最大头部数量"是两个独立的限制，服务器两者都需要。**

| 防御措施 | 防御对象 | 充分性 |
|---|---|---|
| 最大解码头部大小 | 传统 HPACK Bomb（CVE-2016-6581） | 单独不足——被近乎空的头部绕过 |
| 最大头部字段数量（含 cookie 碎屑） | 索引引用炸弹 | **必需**——直接限制放大窗口 |
| 最大重组后 cookie 大小 | Cookie 特定放大 | 部分——不解决非 cookie per-entry 开销 |
| 被卡死流生命周期限制（独立于 WINDOW_UPDATE） | 流控内存固定 | **必需**——防止无限期保留 |
| Per-worker 内存上限（cgroups, ulimit -v） | 爆炸半径遏制 | 最后防线——worker OOM-killed 在主机进入 swap 之前 |

### 各实现配置建议

**nginx 1.29.8+：**
```nginx
max_headers 1000;              # 默认值；应用允许的话可以更低
http2_max_concurrent_streams 32;
http2_max_field_size 4k;
http2_max_header_size 16k;
send_timeout 10s;
```

**Apache httpd（mod_http2 ≥ 2.0.41）：**
```apache
H2MaxSessionStreams 32
LimitRequestFields 100
LimitRequestFieldSize 8190
H2MaxRequestsPerConn 100
```

**Envoy（≥ 1.38.1）：**
```yaml
http_connection_manager:
  max_request_headers_kb: 128
  common_http_protocol_options:
    max_headers_count: 1000
```

---

## 8. AI 在漏洞发现中的角色

HTTP/2 Bomb 的发现过程具有方法论意义。Calif 的 Quang Luong 使用 OpenAI Codex 模型，让它**同时**阅读五个主流 HTTP/2 服务器实现的代码库。攻击的两个组成部分——HPACK Bomb（CVE-2016-6581）和 HTTP/2 Slowloris 变体——已经被公开记录近十年。Codex 识别到的是，这两个技术可以在单条 HTTP/2 连接中被**组合**，产生乘法效应。

这种发现模式——AI 模型有能力同时跨多个独立代码库阅读——揭示了传统逐项目安全审查模式的结构性脆弱。组合存在于团队之间的缝隙中，正如 Calif 所说，"没有人拥有这些缝隙"。

---

## 9. 结论

HTTP/2 Bomb 代表了一类重要的漏洞，位于协议规范、实现多样性和独立理解的原语组合的交汇处。五个主流实现，由各自团队独立研究，各自读了 RFC 7541 §7.3，得出了同一个不完整的内存风险模型。规范将风险纯粹框定为压缩比，加上未考虑 per-entry 分配器开销和流控介导的内存固定，创造了一类潜伏了十年才被跨代码库 AI 分析发现的漏洞。

修复模式在实现之间是一致的：独立地同时执行解码后头部大小限制和头部字段数量限制；将 cookie 碎屑计入字段数量；约束被卡死流的生命周期，无论 `WINDOW_UPDATE` 活动如何。这些原则应该为未来的协议设计提供参考，尤其是随着 HTTP/3 和 QUIC 以其自身的压缩和流控语义变得更加广泛部署。

协调披露过程运转有效：nginx 在通知次日发布修复（2026 年 4 月），Apache 在披露当天提交修复（2026 年 5 月 27 日），Envoy 在公开披露 24 小时内发布补丁（2026 年 6 月 3 日），Microsoft 通过常规 Patch Tuesday 周期跟进（2026 年 6 月 10 日）。响应的速度既反映了漏洞的严重性，也反映了正确识别缺陷后修复的简洁性。

---

## 致谢

感谢 Calif Security Research 的 Quang Luong、Jun Rong 和 Duc Phan 的原始发现和协调披露；Cory Benfield 在 2016 年的原始 HPACK Bomb 研究；Gal Bar Nahum 在 2025 年对 Apache HPACK 放大的独立研究；Stefan Eissing 对 Apache httpd 的当日修复；nginx、Envoy、H2O 和 HAProxy 维护者的快速响应；以及 oss-security 社区为协调披露提供的便利。

特别感谢 **老登（Laodeng）** 慷慨提供的 Ark Coding Plan，支持了本文的研究与写作。

---

## 参考资料

- [RFC 7540 — HTTP/2](https://www.rfc-editor.org/rfc/rfc7540)
- [RFC 7541 — HPACK](https://www.rfc-editor.org/rfc/rfc7541)
- [RFC 9113 — HTTP/2 (修订版)](https://www.rfc-editor.org/rfc/rfc9113)
- [Calif Security Research: Codex Discovered a Hidden HTTP/2 Bomb](https://blog.calif.io/p/codex-discovered-a-hidden-http2-bomb)
- [oss-security: HTTP/2 Bomb affects Apache httpd, nginx, envoy, & pingora](https://seclists.org/oss-sec/2026/q2/790)
- [CVE-2016-6581: HPACK Bomb — Cory Benfield](https://openwall.com/lists/oss-security/2016/08/04/3)
- [Envoy GHSA-22m2-hvr2-xqc8 (CVE-2026-47774)](https://github.com/envoyproxy/envoy/security/advisories/GHSA-22m2-hvr2-xqc8)
- [Apache httpd commit 47d3100b](https://github.com/apache/httpd/commit/47d3100b252dc6668a9e46ae885242be9eeca9cd)
- [nginx commit 3656941](https://github.com/nginx/nginx/commit/365694160a85229a7cb006738de9260d49ff5fa2)
- [H2O GHSA-qcrr-wrhc-pgq9](https://github.com/h2o/h2o/security/advisories/GHSA-qcrr-wrhc-pgq9)
- [HAProxy: Protecting against HTTP/2 Bomb](https://www.haproxy.com/blog/haproxy-cve-2026-49975-http2-bomb)
- [Flowtriq: HTTP/2 Bomb Technical Analysis](https://flowtriq.com/blog/http2-bomb-dos-attack-hpack-compression)
- [lilting.ch: HTTP/2 Bomb 5,700× Envoy, 4,000× Apache amplification](https://lilting.ch/en/articles/http2-bomb-hpack-flow-control-dos)
- [The Register: OpenAI's Codex chains decade-old DoS techniques into HTTP/2 Bomb](https://www.theregister.com/security/2026/06/04/openais-codex-chains-decade-old-dos-techniques-into-http/2-bomb/)
- [CSA Research Note: HTTP/2 Bomb](https://labs.cloudsecurityalliance.org/research/csa-research-note-http2-bomb-ai-discovered-dos-20260604-csa/)
- [Red Hat RHSB-2026-007](https://access.redhat.com/security/vulnerabilities/RHSB-2026-007)
- [Ubuntu CVE-2026-49975](https://ubuntu.com/security/CVE-2026-49975)

---

*本文基于英文原版论文 [http2-bomb-paper.pdf](https://bucket.itedev.com/blog/2026/06/13/3b8762f6cca9147f2f5bb96af84c891a.1781321407.pdf) 翻译并改写，内容保持一致，部分技术细节为适应博客阅读体验做了调整。*
