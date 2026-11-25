# Google One / AI Trial & Discovery Tool

> **Language / Idioma / 语言:** [English](#english) | [Português (Brasil)](#portugues-brasil) | [简体中文](#chinese-zh)

---

<a name="english"></a>
## English

Automated tool for discovering, analyzing, and launching Google Play `BillingClient` subscription offers (including hidden $0.00 trials and promotional tiers) for **Google One** and **Google AI** via Frida.

### How It Works

1. Connects via ADB to a rooted Android emulator (MuMu Player 12, LDPlayer, BlueStacks, or rooted device).
2. Deploys and starts `frida-server` (v16.7.19) and pushes `module.apk` (`com.android.billingclient`) to `/data/local/tmp/` automatically.
3. Injects `frida-auto-trial.js` into Google One (`com.google.android.apps.subscriptions.red`) or another target package (`--pkg`).
4. Queries `BillingClient.queryProductDetailsAsync` in batches, parses `SubscriptionOfferDetails` (`basePlanId`, `offerId`, `offerToken`, `PricingPhase`, `recurrenceMode`), and sorts eligible free trials by duration.
5. Opens the native Google Play payment sheet (`launchBillingFlow`) and keeps Frida attached until you confirm or cancel.

> **Note:** The tool never auto-confirms purchases. Confirmation is always manual inside the emulator.

### Included Files

| File | Purpose |
|---|---|
| `iniciar.bat` | One-click Windows launcher that opens the interactive menu without changing system ExecutionPolicy. |
| `auto-trial.ps1` | Main Windows (PowerShell) runner with menu, discovery, JSON/HTML export, and dynamic ADB port forwarding. |
| `auto-trial.sh` | Linux / macOS shell runner with matching CLI flags and cleanup. |
| `frida-auto-trial.js` | Frida Java hook for `BillingClient`, batch product discovery, live sniffing, and `launchBillingFlow`. |
| `module.apk` | Helper APK providing `com.android.billingclient` classes loaded via `DexClassLoader`. |
| `frida-server.zip` | Bundled `frida-server` v16.7.19 (`x86_64`) extracted and pushed automatically. |

### Prerequisites

1. **Android Emulator / Device with Root** (e.g., MuMu Player 12 with Root enabled).
2. **Google Play Store & Google One** installed and signed in with a valid payment method (free trial eligibility requires an account without an active Google One subscription).
3. **Host PC**:
   - Python 3.9+
   - Frida CLI 16.x matching `frida-server`:
     ```powershell
     pip install "frida==16.7.19" "frida-tools<14.0.0"
     ```
   - ADB (auto-detected from `PATH`, Android SDK, or MuMu installation paths).

### Quick Start (Windows)

**Interactive Menu (Recommended):**
Double-click `iniciar.bat`, or run:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\auto-trial.ps1
```

From the menu you can list/discover offers, pick an offer by number to activate immediately, generate `checkout.html`, or run live `--sniff`.

**CLI Examples:**
```powershell
# List default SKUs and available free trials
.\auto-trial.ps1 --list

# Scan extended SKU dictionary
.\auto-trial.ps1 --scan

# Run combinatorial discovery (2,300+ SKU candidates)
.\auto-trial.ps1 --discover

# Discover offers and export full analysis to JSON or a local web checkout page
.\auto-trial.ps1 --discover --export ofertas.json
.\auto-trial.ps1 --discover --web

# List and select a trial interactively
.\auto-trial.ps1 --interactive

# Activate a specific product/duration or exact offerId
.\auto-trial.ps1 --product pro12 --dur 12mo
.\auto-trial.ps1 --product pro12 --offer 6months-eft-2

# Sniff productIds queried by the app in real time
.\auto-trial.ps1 --sniff
```

### CLI Options

| Flag | Description |
|---|---|
| `--menu` | Open the interactive main menu (default when run with no arguments on Windows). |
| `--list` | Query default Google One SKUs and display available trials/promos. |
| `--scan` | Query an extended curated list of Google One / AI SKUs. |
| `--discover` | Generate and query a combinatorial matrix of candidate SKUs in batches. |
| `--sniff` | Hook `QueryProductDetailsParams` and `BillingFlowParams` to log SKUs queried while browsing the app. |
| `--interactive`, `-i` | List available trials and prompt to activate one by number. |
| `--product <id>` | Target product alias (`pro`, `pro12`, `5x`, `20x`, `auto`) or full `g1.*` SKU. |
| `--dur <period>` | Preferred duration: `1mo`, `3mo`, `6mo`, `12mo`, `longest` (default). |
| `--offer <offerId>` | Activate an exact `offerId` (e.g., `6months-eft-2`). |
| `--extra <id1,id2>` | Append custom comma-separated SKUs to the query. |
| `--promos` | Include discounted introductory offers (non-$0.00) when no free trial is available. |
| `--upgrade` | Attach `SubscriptionUpdateParams` when an active subscription is present. |
| `--export <file>` | Export all discovered offers (including `basePlanId`, phases, savings, and `offerToken`) to JSON. |
| `--web [file]` | Generate a local HTML checkout tester (`checkout.html` by default) using discovered `offerToken`s. |
| `--pkg <package>` | Target package name (default: `com.google.android.apps.subscriptions.red`). |
| `--port <port>` | Specific local MuMu ADB port (e.g., `16416`). |
| `--device <serial>`, `-s` | Specific ADB device serial (e.g., `emulator-5554`). |
| `--timeout <sec>` | Timeout in seconds waiting for payment confirmation or sniff (default: `180`). |
| `--adb <path>` | Custom path to `adb`. |
| `--script <path>` | Custom path to Frida JS script. |
| `-h`, `--help` | Show CLI help. |

### Product Aliases & Known SKUs

| Alias | Product ID | Plan |
|---|---|---|
| `pro12` | `g1.2tb.ai.subs_variant` | Google AI Pro (5 TB) — extended trials (up to 12 months) |
| `pro` | `g1.play.2tb.ai` | Google AI Pro (5 TB) — standard trial (e.g. 3 months) |
| `5x` | `g1.play.20tb` | Google AI Ultra (20 TB) |
| `20x` | `g1.play.ai.pro` | Google AI Ultra (30 TB) |
| — | `g1.2tb.subs_variant` | Google AI Plus (2 TB) — promotional trials (3 / 6 months) |
| — | `g1.play.2tb.ai.student` | Google AI Pro (5 TB) — student pricing |
| — | `g1.10tb`, `g1.20tb.v2`, `g1.ai.pro` | Additional high-tier storage / Ultra SKUs |

---

<a name="portugues-brasil"></a>
## Português (Brasil)

Ferramenta automatizada para descobrir, analisar e abrir ofertas de assinatura do Google Play `BillingClient` (incluindo trials grátis de R$ 0,00 e variantes promocionais) para **Google One** e **Google AI** via Frida.

### Como funciona

1. Conecta via ADB a um emulador Android com root (MuMu Player 12, LDPlayer, BlueStacks ou aparelho físico com root).
2. Extrai e inicia automaticamente o `frida-server` (v16.7.19) e envia o `module.apk` (`com.android.billingclient`) para `/data/local/tmp/`.
3. Injeta o `frida-auto-trial.js` no Google One (`com.google.android.apps.subscriptions.red`) ou em outro pacote alvo (`--pkg`).
4. Consulta `BillingClient.queryProductDetailsAsync` em lotes, lê `SubscriptionOfferDetails` (`basePlanId`, `offerId`, `offerToken`, `PricingPhase`, `recurrenceMode`) e ordena os trials por duração.
5. Abre a janela oficial de pagamento da Google Play (`launchBillingFlow`) e mantém o Frida ativo até você confirmar ou cancelar.

> **Observação:** O script nunca confirma compras automaticamente. A confirmação é sempre manual dentro do emulador.

### Arquivos inclusos

| Arquivo | Função |
|---|---|
| `iniciar.bat` | Atalho de 1 clique no Windows para abrir o menu interativo sem alterar a ExecutionPolicy do sistema. |
| `auto-trial.ps1` | Script principal para Windows (PowerShell) com menu, descoberta de planos, exportação JSON/HTML e redirecionamento dinâmico de porta ADB. |
| `auto-trial.sh` | Script shell para Linux / macOS com as mesmas flags principais e limpeza automática. |
| `frida-auto-trial.js` | Hook Frida Java para `BillingClient`, varredura em lotes, sniff em tempo real e `launchBillingFlow`. |
| `module.apk` | APK auxiliar com a biblioteca `com.android.billingclient` carregada via `DexClassLoader`. |
| `frida-server.zip` | Binário `frida-server` v16.7.19 (`x86_64`) extraído e enviado automaticamente. |

### Pré-requisitos

1. **Emulador Android ou aparelho com Root** (ex.: MuMu Player 12 com Root ativado).
2. **Google Play Store e Google One** instalados e logados em uma conta com método de pagamento válido (para elegibilidade de trial grátis, a conta não pode ter assinatura Google One ativa).
3. **No PC**:
   - Python 3.9+
   - Frida CLI 16.x compatível com o `frida-server`:
     ```powershell
     pip install "frida==16.7.19" "frida-tools<14.0.0"
     ```
   - ADB (detectado automaticamente no `PATH`, Android SDK ou pasta do MuMu).

### Início Rápido (Windows)

**Menu Interativo (Recomendado):**
Dê duplo clique em `iniciar.bat`, ou execute:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\auto-trial.ps1
```

No menu você pode listar/varrer ofertas, escolher qual ativar pelo número na hora, gerar `checkout.html` ou rodar o `--sniff`.

**Exemplos via linha de comando:**
```powershell
# Listar SKUs padrão e trials disponíveis
.\auto-trial.ps1 --list

# Varrer dicionário ampliado de SKUs
.\auto-trial.ps1 --scan

# Executar descoberta combinatória (2.300+ IDs candidatos)
.\auto-trial.ps1 --discover

# Descobrir ofertas e exportar análise completa em JSON ou checkout web local
.\auto-trial.ps1 --discover --export ofertas.json
.\auto-trial.ps1 --discover --web

# Listar e escolher uma avaliação interativamente
.\auto-trial.ps1 --interactive

# Ativar por produto/duração ou offerId exato
.\auto-trial.ps1 --product pro12 --dur 12mo
.\auto-trial.ps1 --product pro12 --offer 6months-eft-2

# Interceptar em tempo real os SKUs consultados pelo app
.\auto-trial.ps1 --sniff
```

### Opções de Linha de Comando

| Flag | Descrição |
|---|---|
| `--menu` | Abre o menu principal interativo (padrão ao rodar sem argumentos no Windows). |
| `--list` | Consulta os SKUs padrão do Google One e exibe trials/promos disponíveis. |
| `--scan` | Consulta uma lista ampliada de SKUs conhecidos do Google One / AI. |
| `--discover` | Gera e consulta em lotes uma matriz combinatória de SKUs candidatos. |
| `--sniff` | Faz hook em `QueryProductDetailsParams` e `BillingFlowParams` para exibir SKUs consultados ao navegar no app. |
| `--interactive`, `-i` | Lista os trials disponíveis e permite escolher pelo número para ativar. |
| `--product <id>` | Apelido do produto (`pro`, `pro12`, `5x`, `20x`, `auto`) ou ID completo `g1.*`. |
| `--dur <período>` | Duração preferida: `1mo`, `3mo`, `6mo`, `12mo`, `longest` (padrão). |
| `--offer <offerId>` | Ativa um `offerId` específico (ex.: `6months-eft-2`). |
| `--extra <id1,id2>` | Adiciona SKUs extras separados por vírgula na consulta. |
| `--promos` | Inclui ofertas com desconto introdutório (não R$ 0,00) quando não houver trial grátis. |
| `--upgrade` | Anexa `SubscriptionUpdateParams` quando houver assinatura ativa. |
| `--export <arquivo>` | Exporta todas as ofertas encontradas (`basePlanId`, fases, economia e `offerToken`) para JSON. |
| `--web [arquivo]` | Gera um testador HTML local (`checkout.html` por padrão) com os `offerToken`s reais. |
| `--pkg <pacote>` | Define o pacote alvo (padrão: `com.google.android.apps.subscriptions.red`). |
| `--port <porta>` | Porta ADB local específica do MuMu (ex.: `16416`). |
| `--device <serial>`, `-s` | Serial ADB específico do dispositivo (ex.: `emulator-5554`). |
| `--timeout <seg>` | Tempo máximo em segundos aguardando confirmação ou sniff (padrão: `180`). |
| `--adb <caminho>` | Caminho customizado para o `adb`. |
| `--script <caminho>` | Caminho customizado para o script JS do Frida. |
| `-h`, `--help` | Exibe a ajuda. |

### Apelidos e SKUs Conhecidos

| Apelido | ID do Produto | Plano |
|---|---|---|
| `pro12` | `g1.2tb.ai.subs_variant` | Google AI Pro (5 TB) — trials estendidos (até 12 meses) |
| `pro` | `g1.play.2tb.ai` | Google AI Pro (5 TB) — trial padrão (ex.: 3 meses) |
| `5x` | `g1.play.20tb` | Google AI Ultra (20 TB) |
| `20x` | `g1.play.ai.pro` | Google AI Ultra (30 TB) |
| — | `g1.2tb.subs_variant` | Google AI Plus (2 TB) — trials promocionais (3 / 6 meses) |
| — | `g1.play.2tb.ai.student` | Google AI Pro (5 TB) — tarifa estudante |
| — | `g1.10tb`, `g1.20tb.v2`, `g1.ai.pro` | Outros SKUs de planos maiores / Ultra |

---

<a name="chinese-zh"></a>
## 简体中文

基于 Frida 注入 Google Play `BillingClient` 的自动化工具，用于发现、分析并拉起 **Google One** 与 **Google AI** 的隐藏免费试用（$0.00）及促销订阅优惠。

### 工作原理

1. 通过 ADB 连接已开启 Root 的 Android 模拟器（MuMu 模拟器 12、雷电、BlueStacks 或已 Root 实体机）。
2. 自动解压并启动 `frida-server`（v16.7.19），并将包含 `com.android.billingclient` 的 `module.apk` 推送至 `/data/local/tmp/`。
3. 将 `frida-auto-trial.js` 注入 Google One（`com.google.android.apps.subscriptions.red`）或指定的目标包名（`--pkg`）。
4. 分批调用 `BillingClient.queryProductDetailsAsync`，解析 `SubscriptionOfferDetails`（`basePlanId`、`offerId`、`offerToken`、`PricingPhase`、`recurrenceMode`），并按试用时长排序。
5. 拉起 Google Play 原生支付弹窗（`launchBillingFlow`），并保持 Frida 挂载直到你在模拟器中完成确认或取消。

> **说明：** 脚本不会自动完成扣款确认，所有支付操作均需在模拟器内手动确认。

### 包含文件

| 文件 | 用途 |
|---|---|
| `iniciar.bat` | Windows 一键启动脚本，无需修改系统 ExecutionPolicy 即可打开交互菜单。 |
| `auto-trial.ps1` | Windows (PowerShell) 主控制脚本，支持交互菜单、批量扫描、JSON/HTML 导出及动态 ADB 端口转发。 |
| `auto-trial.sh` | Linux / macOS Shell 脚本，包含相同的核心参数与退出清理逻辑。 |
| `frida-auto-trial.js` | Frida Java Hook 脚本，负责加载 `BillingClient`、批量查询 SKU、实时抓包和发起支付流程。 |
| `module.apk` | 通过 `DexClassLoader` 提供官方 `com.android.billingclient` 类的辅助 APK。 |
| `frida-server.zip` | 内置 `frida-server` v16.7.19 (`x86_64`)，脚本会自动解压并推送至设备。 |

### 环境要求

1. **已开启 Root 的 Android 模拟器或设备**（推荐 MuMu 模拟器 12 并开启 Root 权限）。
2. **已安装 Google Play 商店与 Google One**，并登录了绑定有效付款方式的 Google 账号（免费试用通常要求账号当前无生效中的 Google One 订阅）。
3. **电脑端依赖**：
   - Python 3.9+
   - 与 `frida-server` 主版本一致的 Frida CLI 16.x：
     ```powershell
     pip install "frida==16.7.19" "frida-tools<14.0.0"
     ```
   - ADB（脚本会自动从 `PATH`、Android SDK 或 MuMu 目录检测）。

### 快速开始 (Windows)

**交互式菜单（推荐）：**
双击 `iniciar.bat`，或直接无参数运行：
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\auto-trial.ps1
```

在菜单中可直接列出/发现优惠、按编号选择立即激活、生成 `checkout.html` 或开启实时 `--sniff`。

**命令行示例：**
```powershell
# 列出默认 SKU 与可用免费试用
.\auto-trial.ps1 --list

# 扫描扩展 SKU 词库
.\auto-trial.ps1 --scan

# 组合矩阵探测（2,300+ 候选 SKU）
.\auto-trial.ps1 --discover

# 发现优惠并导出完整 JSON 分析或生成本地网页结账测试页
.\auto-trial.ps1 --discover --export ofertas.json
.\auto-trial.ps1 --discover --web

# 列出并按编号交互选择激活
.\auto-trial.ps1 --interactive

# 指定产品/时长或精确 offerId 激活
.\auto-trial.ps1 --product pro12 --dur 12mo
.\auto-trial.ps1 --product pro12 --offer 6months-eft-2

# 实时嗅探应用内查询的 SKU
.\auto-trial.ps1 --sniff
```

### 命令行参数

| 参数 | 说明 |
|---|---|
| `--menu` | 打开交互式主菜单（Windows 无参数运行时的默认行为）。 |
| `--list` | 查询默认 Google One SKU 并显示可用试用/促销。 |
| `--scan` | 查询扩展的预设 Google One / AI SKU 列表。 |
| `--discover` | 生成并分批查询组合矩阵候选 SKU。 |
| `--sniff` | Hook `QueryProductDetailsParams` 与 `BillingFlowParams`，实时记录浏览应用时请求的 SKU。 |
| `--interactive`, `-i` | 列出可用试用并按编号提示选择激活。 |
| `--product <id>` | 产品别名（`pro`、`pro12`、`5x`、`20x`、`auto`）或完整 `g1.*` SKU。 |
| `--dur <period>` | 偏好时长：`1mo`、`3mo`、`6mo`、`12mo`、`longest`（默认）。 |
| `--offer <offerId>` | 精确激活指定的 `offerId`（例如 `6months-eft-2`）。 |
| `--extra <id1,id2>` | 追加逗号分隔的自定义 SKU 一起查询。 |
| `--promos` | 当无免费试用时，包含首期折扣优惠（非 $0.00）。 |
| `--upgrade` | 在已有订阅时附加 `SubscriptionUpdateParams`。 |
| `--export <file>` | 将发现的所有优惠（含 `basePlanId`、阶段、节省金额及 `offerToken`）导出为 JSON。 |
| `--web [file]` | 使用获取到的 `offerToken` 生成本地 HTML 结账测试页（默认为 `checkout.html`）。 |
| `--pkg <package>` | 指定目标应用包名（默认：`com.google.android.apps.subscriptions.red`）。 |
| `--port <port>` | 指定 MuMu 本地 ADB 端口（例如 `16416`）。 |
| `--device <serial>`, `-s` | 指定 ADB 设备序列号（例如 `emulator-5554`）。 |
| `--timeout <sec>` | 等待支付确认或 sniff 的超时秒数（默认：`180`）。 |
| `--adb <path>` | 自定义 `adb` 路径。 |
| `--script <path>` | 自定义 Frida JS 脚本路径。 |
| `-h`, `--help` | 显示帮助信息。 |

### 产品别名与已知 SKU

| 别名 | 产品 ID | 方案 |
|---|---|---|
| `pro12` | `g1.2tb.ai.subs_variant` | Google AI Pro (5 TB) — 扩展试用（最长 12 个月） |
| `pro` | `g1.play.2tb.ai` | Google AI Pro (5 TB) — 标准试用（例如 3 个月） |
| `5x` | `g1.play.20tb` | Google AI Ultra (20 TB) |
| `20x` | `g1.play.ai.pro` | Google AI Ultra (30 TB) |
| — | `g1.2tb.subs_variant` | Google AI Plus (2 TB) — 促销试用（3 / 6 个月） |
| — | `g1.play.2tb.ai.student` | Google AI Pro (5 TB) — 学生优惠 |
| — | `g1.10tb`, `g1.20tb.v2`, `g1.ai.pro` | 其他高容量 / Ultra SKU |
