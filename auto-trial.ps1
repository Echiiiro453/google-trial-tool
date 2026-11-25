# auto-trial.ps1 — Ativação automatizada de avaliações gratuitas do Google One / Gemini Advanced
#
# Uso:
#   .\auto-trial.ps1 --list                        # exibe todas as avaliações disponíveis
#   .\auto-trial.ps1 --scan                        # varre dicionário amplo de IDs de planos
#   .\auto-trial.ps1 --discover                    # gera matriz combinatória (~650+ IDs) e testa na Play Store
#   .\auto-trial.ps1 --sniff                       # intercepta IDs consultados pelo app em tempo real
#   .\auto-trial.ps1 --extra id1,id2 --list        # testa IDs extras junto com os padrões
#   .\auto-trial.ps1 --promos --product 20x        # inclui promoções com desconto se não houver $0.00
#   .\auto-trial.ps1 --offer 6months-eft-2         # ativa exatamente um offerId específico
#   .\auto-trial.ps1 --discover --export out.json  # exporta análise completa de ofertas em JSON
#   .\auto-trial.ps1 --discover --web              # gera checkout.html com tokens reais para testar no navegador
#   .\auto-trial.ps1 --interactive                 # lista e permite escolher qual avaliação ativar
#   .\auto-trial.ps1 --product 20x --dur 12mo      # Ultra 20x, avaliação de 12 meses
#   .\auto-trial.ps1 --product 5x --dur 6mo        # Ultra 5x, avaliação de 6 meses
#   .\auto-trial.ps1 --product pro --dur 3mo        # Pro 5TB, avaliação de 3 meses
#   .\auto-trial.ps1 --product pro12 --dur 12mo     # Variante Pro 5TB, avaliação de 12 meses
#   .\auto-trial.ps1 --product 20x                  # Ultra 20x, maior duração disponível
#   .\auto-trial.ps1 --port 16416 --list            # especifica a porta ADB do MuMu
#   .\auto-trial.ps1 --device emulator-5554 --list  # especifica o serial ADB do dispositivo
#   .\auto-trial.ps1 --pkg com.google.android.apps.photos --sniff  # injeta em outro app Google
#   .\auto-trial.ps1 --timeout 180 --product 20x    # tempo máximo (s) aguardando confirmação
#
# Produtos: pro = g1.play.2tb.ai ($19.99), pro12 = g1.2tb.ai.subs_variant ($19.99, até 12 meses de avaliação),
#           5x = g1.play.20tb ($99.99), 20x = g1.play.ai.pro ($199.99), auto = melhor correspondência
# Durações: 1mo, 3mo, 6mo, 12mo, longest (padrão)
#
# A janela de pagamento é aberta, mas NÃO confirmada automaticamente — confirme manualmente (senha necessária).
#
# Requisitos: adb (incluso no MuMu), frida CLI, frida-server no dispositivo, module.apk no dispositivo

$ErrorActionPreference = "Stop"
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8

# ===== Caminhos =====
$SCRIPT_DIR = $PSScriptRoot
$FRIDA_SCRIPT = if ($env:FRIDA_SCRIPT) { $env:FRIDA_SCRIPT } else { Join-Path $SCRIPT_DIR "frida-auto-trial.js" }
$FRIDA_DEVICE_PORT = 27042
$script:FRIDA_LOCAL_PORT = 27043
$GOOGLE_ONE_PKG = "com.google.android.apps.subscriptions.red"

# Caminhos no dispositivo (sobrescreva via variáveis de ambiente se a estrutura for diferente)
$MODULE_APK_DEVICE = if ($env:MODULE_APK_DEVICE) { $env:MODULE_APK_DEVICE } else { "/data/local/tmp/module.apk" }
$FRIDA_SERVER_PATH = if ($env:FRIDA_SERVER_PATH) { $env:FRIDA_SERVER_PATH } else { "/data/local/tmp/frida-server" }

# ===== Padrões =====
$MODE = "activate"
$INTERACTIVE = $false
$TARGET = "auto"
$DURATION = "longest"
$DEVICE_PORT = ""
$DEVICE_SERIAL = ""
$ADB_OVERRIDE = ""
$WAIT_TIMEOUT = 180
$EXTRA_PRODUCTS = ""
$INCLUDE_PROMOS = $false
$UPGRADE_MODE = $false
$OLD_PURCHASE_TOKEN = ""
$REPLACE_MODE = 5
$TARGET_OFFER = ""
$EXPORT_PATH = ""
$WEB_OUT = ""
$SHOW_MENU = ($args.Count -eq 0)
$UI_LANG = "pt"
$LANG_EXPLICIT = $false

# ===== Auxiliares =====
function Write-Log($msg) { Write-Host "[*] $msg" }
function Write-Ok($msg)  { Write-Host "[+] $msg" -ForegroundColor Green }
function Write-Warn($msg){ Write-Host "[!] $msg" -ForegroundColor Yellow }
function Write-Err($msg) { Write-Host "[-] $msg" -ForegroundColor Red }
function Stop-WithError($msg) { Write-Err $msg; exit 1 }

function Get-FreeTcpPort {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    try {
        $listener.Start()
        return ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
    } finally {
        $listener.Stop()
    }
}

function ConvertTo-JsStringLiteral([string]$val) {
    $escaped = $val.Replace('\', '\\').Replace('"', '\"').Replace("`r", '\r').Replace("`n", '\n')
    return "`"$escaped`""
}

function Show-Help {
    $lines = Get-Content $PSCommandPath
    foreach ($line in $lines) {
        if ($line -match '^# ?(.*)$') {
            Write-Host $Matches[1]
        } elseif ([string]::IsNullOrWhiteSpace($line)) {
            break
        }
    }
    exit 0
}

# ===== Analisar argumentos =====
$i = 0
while ($i -lt $args.Count) {
    $arg = $args[$i]
    switch -Regex ($arg) {
        '^(-list|--list)$' {
            $MODE = "list"
            $i++
        }
        '^(-scan|--scan)$' {
            $MODE = "scan"
            $i++
        }
        '^(-discover|--discover)$' {
            $MODE = "discover"
            $i++
        }
        '^(-sniff|--sniff)$' {
            $MODE = "sniff"
            $i++
        }
        '^(-promos|--promos)$' {
            $INCLUDE_PROMOS = $true
            $i++
        }
        '^(-upgrade|--upgrade|-stack|--stack)$' {
            $UPGRADE_MODE = $true
            $i++
        }
        '^(-old-token|--old-token)$' {
            if ($i + 1 -ge $args.Count) { Stop-WithError "Faltando valor para $arg" }
            $OLD_PURCHASE_TOKEN = $args[$i + 1]
            $UPGRADE_MODE = $true
            $i += 2
        }
        '^(-replace-mode|--replace-mode)$' {
            if ($i + 1 -ge $args.Count) { Stop-WithError "Faltando valor para $arg" }
            $REPLACE_MODE = [int]$args[$i + 1]
            $i += 2
        }
        '^(-extra|--extra)$' {
            if ($i + 1 -ge $args.Count) { Stop-WithError "Faltando valor para $arg" }
            $EXTRA_PRODUCTS = $args[$i + 1]
            $i += 2
        }
        '^(-offer|--offer)$' {
            if ($i + 1 -ge $args.Count) { Stop-WithError "Faltando valor para $arg" }
            $TARGET_OFFER = $args[$i + 1]
            $i += 2
        }
        '^(-export|--export)$' {
            if ($i + 1 -ge $args.Count) { Stop-WithError "Faltando valor para $arg" }
            $EXPORT_PATH = $args[$i + 1]
            $i += 2
        }
        '^(-web|--web)$' {
            if ($i + 1 -lt $args.Count -and -not $args[$i + 1].StartsWith('-')) {
                $WEB_OUT = $args[$i + 1]
                $i += 2
            } else {
                $WEB_OUT = Join-Path $SCRIPT_DIR "checkout.html"
                $i++
            }
        }
        '^(-i|-interactive|--interactive)$' {
            $INTERACTIVE = $true
            $MODE = "list"
            $i++
        }
        '^(-menu|--menu)$' {
            $SHOW_MENU = $true
            $i++
        }
        '^(-lang|--lang)$' {
            if ($i + 1 -ge $args.Count) { Stop-WithError "Faltando valor para $arg" }
            $langVal = $args[$i + 1].ToLowerInvariant()
            if ($langVal -in @("pt", "en", "zh")) {
                $UI_LANG = $langVal
                $LANG_EXPLICIT = $true
            } else {
                Stop-WithError "Idioma inválido: $($args[$i + 1]) (use pt, en ou zh)"
            }
            $i += 2
        }
        '^(-product|--product)$' {
            if ($i + 1 -ge $args.Count) { Stop-WithError "Faltando valor para $arg" }
            $TARGET = $args[$i + 1]
            $i += 2
        }
        '^(-dur|--dur|-duration|--duration)$' {
            if ($i + 1 -ge $args.Count) { Stop-WithError "Faltando valor para $arg" }
            $DURATION = $args[$i + 1]
            $i += 2
        }
        '^(-port|--port)$' {
            if ($i + 1 -ge $args.Count) { Stop-WithError "Faltando valor para $arg" }
            $DEVICE_PORT = $args[$i + 1]
            $i += 2
        }
        '^(-device|--device|-s)$' {
            if ($i + 1 -ge $args.Count) { Stop-WithError "Faltando valor para $arg" }
            $DEVICE_SERIAL = $args[$i + 1]
            $i += 2
        }
        '^(-pkg|--pkg)$' {
            if ($i + 1 -ge $args.Count) { Stop-WithError "Faltando valor para $arg" }
            $GOOGLE_ONE_PKG = $args[$i + 1]
            $i += 2
        }
        '^(-timeout|--timeout)$' {
            if ($i + 1 -ge $args.Count) { Stop-WithError "Faltando valor para $arg" }
            $parsedTimeout = 0
            if (-not [int]::TryParse($args[$i + 1], [ref]$parsedTimeout) -or $parsedTimeout -lt 10) {
                Stop-WithError "Valor inválido para ${arg}: $($args[$i + 1]) (use inteiro >= 10)"
            }
            $WAIT_TIMEOUT = $parsedTimeout
            $i += 2
        }
        '^(-adb|--adb)$' {
            if ($i + 1 -ge $args.Count) { Stop-WithError "Faltando valor para $arg" }
            $ADB_OVERRIDE = $args[$i + 1]
            $i += 2
        }
        '^(-script|--script)$' {
            if ($i + 1 -ge $args.Count) { Stop-WithError "Faltando valor para $arg" }
            $FRIDA_SCRIPT = $args[$i + 1]
            $i += 2
        }
        '^(-h|--help|-help)$' {
            Show-Help
        }
        default {
            Stop-WithError "Opção desconhecida: $arg"
        }
    }
}

# ===== Detectar ADB automaticamente =====
function Find-Adb {
    if ($ADB_OVERRIDE) {
        if (Test-Path -LiteralPath $ADB_OVERRIDE -PathType Leaf) { return $ADB_OVERRIDE }
        Stop-WithError "adb especificado não encontrado: $ADB_OVERRIDE"
    }
    # 1. Variável de ambiente explícita
    if ($env:ADB_PATH -and (Test-Path -LiteralPath $env:ADB_PATH -PathType Leaf)) {
        return $env:ADB_PATH
    }
    # 2. PATH
    $cmd = Get-Command adb -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }
    # 3. Locais conhecidos do adb no Windows (MuMu e Android SDK)
    $candidates = @(
        "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
        "$env:PROGRAMFILES\Android\android-sdk\platform-tools\adb.exe",
        "$env:ProgramFiles\Netease\MuMuPlayer-12.0\shell\adb.exe",
        "$env:ProgramFiles\Netease\MuMu Player 12\shell\adb.exe",
        "$env:ProgramFiles\Netease\MuMuPlayerGlobal-12.0\shell\adb.exe",
        "$env:ProgramFiles\Netease\MuMuPlayer\shell\adb.exe",
        "${env:ProgramFiles(x86)}\Netease\MuMuPlayer-12.0\shell\adb.exe",
        "${env:ProgramFiles(x86)}\Netease\MuMuPlayer\shell\adb.exe",
        "C:\Program Files\Netease\MuMuPlayer-12.0\shell\adb.exe",
        "C:\Program Files\Netease\MuMu Player 12\shell\adb.exe",
        "C:\Program Files\Netease\MuMuPlayerGlobal-12.0\shell\adb.exe",
        "D:\Program Files\Netease\MuMuPlayer-12.0\shell\adb.exe",
        "D:\Program Files\Netease\MuMu Player 12\shell\adb.exe",
        "D:\Program Files\Netease\MuMuPlayerGlobal-12.0\shell\adb.exe"
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c -PathType Leaf)) {
            return $c
        }
    }
    return $null
}

$ADB = Find-Adb
if (-not $ADB) {
    Stop-WithError "adb não encontrado. Instale o Android SDK / MuMu ou defina a variável de ambiente ADB_PATH"
}

# ===== Resolver apelidos dos produtos =====
switch -Regex ($TARGET) {
    '^(20x|ultra20x)$' { $TARGET = "g1.play.ai.pro" }
    '^(5x|ultra5x)$'   { $TARGET = "g1.play.20tb" }
    '^pro$'            { $TARGET = "g1.play.2tb.ai" }
    '^pro12$'          { $TARGET = "g1.2tb.ai.subs_variant" }
    '^(auto|g1\..*)$'  { } # manter como está
    default {
        Stop-WithError "Produto desconhecido: $TARGET (use pro, 5x, 20x, pro12 ou um ID de produto g1.*)"
    }
}

$script:DEVICE = ""

# ===== 1. Encontrar dispositivo ADB / MuMu =====
function Find-Device {
    if ($DEVICE_SERIAL) {
        $script:DEVICE = $DEVICE_SERIAL
        Write-Log "Usando dispositivo especificado $script:DEVICE"
        if ($DEVICE_SERIAL -match '^\S+:\d+$') {
            try { & $ADB connect $script:DEVICE *>$null } catch {}
        }
        $state = try { (& $ADB -s $script:DEVICE get-state 2>$null) -join "" } catch { "" }
        if ($state.Trim() -ne "device") {
            Stop-WithError "Dispositivo '$DEVICE_SERIAL' não está pronto (estado: '$($state.Trim())')"
        }
        return
    }

    if ($DEVICE_PORT) {
        $script:DEVICE = "127.0.0.1:$DEVICE_PORT"
        Write-Log "Usando dispositivo especificado $script:DEVICE"
        try { & $ADB connect $script:DEVICE *>$null } catch {}
        return
    }

    Write-Log "Procurando dispositivos MuMu..."
    # Portas do MuMu: 16384, 16416, 16448, 16480, 16512, 7555
    foreach ($port in @(16384, 16416, 16448, 16480, 16512, 7555)) {
        $out = try { & $ADB connect "127.0.0.1:$port" 2>$null } catch { "" }
        if (($out -join "`n") -match "connected") {
            $script:DEVICE = "127.0.0.1:$port"
            Write-Ok "Dispositivo encontrado em $script:DEVICE"
            return
        }
    }

    # Alternativa: verificar dispositivos já conectados (LDPlayer, BlueStacks, USB, etc.)
    $devs = try { & $ADB devices 2>$null } catch { @() }
    foreach ($line in $devs) {
        if ($line -notmatch "^List" -and $line -match "^(\S+)\s+device\s*$") {
            $script:DEVICE = $Matches[1]
            Write-Ok "Usando dispositivo conectado $script:DEVICE"
            return
        }
    }

    Stop-WithError "Nenhum dispositivo encontrado. Inicie o emulador ou use --port <PORTA> / --device <SERIAL>"
}

# ===== Detectar Frida CLI automaticamente =====
function Find-Frida {
    if ($env:FRIDA_BIN -and (Test-Path -LiteralPath $env:FRIDA_BIN -PathType Leaf)) {
        return $env:FRIDA_BIN
    }
    $candidates = @()
    $cmd = Get-Command frida -All -ErrorAction SilentlyContinue
    if ($cmd) {
        $candidates += ($cmd | ForEach-Object { $_.Source })
    }
    $pyDirs = Get-ChildItem -Path "$env:LOCALAPPDATA\Programs\Python\Python*\Scripts\frida.exe", "$env:LOCALAPPDATA\Python\pythoncore-*\Scripts\frida.exe" -ErrorAction SilentlyContinue
    if ($pyDirs) {
        $candidates += ($pyDirs | ForEach-Object { $_.FullName })
    }
    $candidates = $candidates | Select-Object -Unique
    # Priorizar Frida 16.x (compatível com frida-server 16.x e com ponte Java embutida)
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c -PathType Leaf)) {
            $ver = try { (& $c --version 2>$null) -join "" } catch { "" }
            if ($ver.Trim() -match '^16\.') {
                return $c
            }
        }
    }
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c -PathType Leaf)) {
            return $c
        }
    }
    return $null
}

function Test-FridaVersion($fridaBin) {
    $cliVer = try { (& $fridaBin --version 2>$null) -join "" } catch { "" }
    $cliVer = $cliVer.Trim()
    if (-not $cliVer) { return }

    Write-Log "Frida CLI local detectado: v$cliVer ($fridaBin)"

    if ($cliVer -match '^(\d+)\.') {
        $majorCli = [int]$Matches[1]
        if ($majorCli -ne 16) {
            Write-Host ""
            Write-Err "=========================================================================="
            Write-Err "VERSÃO INCOMPATÍVEL DO FRIDA DETECTADA: v$cliVer"
            Write-Err "O frida-server incluído no projeto é a versão 16.7.19."
            Write-Err "O Frida exige que a versão principal (major) seja IDÊNTICA (16.x com 16.x)."
            Write-Err "Com Frida 17.x no PC, ocorre o erro:"
            Write-Err "'Failed to attach: unable to communicate with remote frida-server'."
            Write-Err "=========================================================================="
            Write-Host ""
            Write-Host ">>> COMO RESOLVER AGORA (execute no PowerShell / CMD):" -ForegroundColor Yellow
            Write-Host '    pip install "frida==16.7.19" "frida-tools<14.0.0" --force-reinstall' -ForegroundColor Green
            Write-Host ""
            Stop-WithError "Versão incompatível do Frida CLI. Reinstale a v16.7.19 com o comando acima e tente novamente."
        }
    }
}

# ===== 2. Configurar Frida =====
function Initialize-Frida {
    # Garantir que o adbd esteja rodando como root no MuMu
    $shell_uid = try { (& $ADB -s $script:DEVICE shell "id -u" 2>$null) -join "" } catch { "" }
    if ($shell_uid.Trim() -ne "0") {
        Write-Log "Elevando adbd para root..."
        try { & $ADB -s $script:DEVICE root *>$null } catch {}
        Start-Sleep -Seconds 2
        try { & $ADB connect $script:DEVICE *>$null } catch {}
    }

    $script:FRIDA_LOCAL_PORT = Get-FreeTcpPort
    Write-Log "Configurando redirecionamento de porta do Frida ($($script:FRIDA_LOCAL_PORT) -> $FRIDA_DEVICE_PORT)..."
    try { & $ADB -s $script:DEVICE forward "tcp:$($script:FRIDA_LOCAL_PORT)" "tcp:$FRIDA_DEVICE_PORT" 2>$null | Out-Null } catch {}

    # Verificar arquitetura do dispositivo
    $abi = try { (& $ADB -s $script:DEVICE shell "getprop ro.product.cpu.abi" 2>$null) -join "" } catch { "" }
    $abi = $abi.Trim()
    if ($abi) {
        Write-Log "Arquitetura (ABI) do dispositivo: $abi"
        if ($abi -notmatch "x86_64") {
            Write-Host "[!] AVISO: A ABI do seu emulador é '$abi' (o frida-server padrão incluído é x86_64)." -ForegroundColor Yellow
            Write-Host "    Se o frida-server não iniciar, baixe o binário para '$abi' (v16.7.19) em:" -ForegroundColor Yellow
            Write-Host "    https://github.com/frida/frida/releases/tag/16.7.19" -ForegroundColor Cyan
        }
    }

    # Verificar se o frida-server está rodando e se está como root
    $fs_pid = try { (& $ADB -s $script:DEVICE shell "pidof frida-server" 2>$null) -join "" } catch { "" }
    $fs_pid = $fs_pid.Trim()

    if ($fs_pid) {
        # Verificar versão do frida-server atualmente em execução
        $fs_ver = try { (& $ADB -s $script:DEVICE shell "$FRIDA_SERVER_PATH --version" 2>$null) -join "" } catch { "" }
        $fs_ver = $fs_ver.Trim()
        if ($fs_ver -and $fs_ver -notmatch '^16\.') {
            Write-Log "frida-server ativo é v$fs_ver (diferente de 16.x); reiniciando com versão compatível 16.7.19..."
            try { & $ADB -s $script:DEVICE shell "kill -9 $fs_pid" 2>$null | Out-Null } catch {}
            Start-Sleep -Seconds 1
            $fs_pid = ""
        }
    }

    if ($fs_pid) {
        $fs_user = try { (& $ADB -s $script:DEVICE shell "ps -o USER= -p $fs_pid" 2>$null) -join "" } catch { "" }
        if ($fs_user.Trim() -and $fs_user.Trim() -ne "root") {
            Write-Log "frida-server rodando como '$($fs_user.Trim())' (sem root); reiniciando como root..."
            try { & $ADB -s $script:DEVICE shell "kill -9 $fs_pid" 2>$null | Out-Null } catch {}
            Start-Sleep -Seconds 1
            $fs_pid = ""
        }
    }

    if (-not $fs_pid) {
        # Se frida-server não existir no dispositivo, envia automaticamente se presente na pasta local
        $fs_exists = try { (& $ADB -s $script:DEVICE shell "test -f $FRIDA_SERVER_PATH && echo 1" 2>$null) -join "" } catch { "" }
        if ($fs_exists.Trim() -ne "1") {
            $local_fs = Join-Path $SCRIPT_DIR "frida-server"
            $local_zip = Join-Path $SCRIPT_DIR "frida-server.zip"
            if (-not (Test-Path -LiteralPath $local_fs -PathType Leaf) -and (Test-Path -LiteralPath $local_zip -PathType Leaf)) {
                Write-Log "Extraindo frida-server.zip..."
                try { Expand-Archive -Path $local_zip -DestinationPath $SCRIPT_DIR -Force } catch {}
            }
            if (Test-Path -LiteralPath $local_fs -PathType Leaf) {
                Write-Log "frida-server não encontrado no dispositivo. Enviando $local_fs para $FRIDA_SERVER_PATH..."
                try { & $ADB -s $script:DEVICE push $local_fs $FRIDA_SERVER_PATH *>$null } catch {}
                try { & $ADB -s $script:DEVICE shell "chmod 755 $FRIDA_SERVER_PATH" *>$null } catch {}
            }
        }

        Write-Log "Iniciando frida-server como root..."
        try { & $ADB -s $script:DEVICE shell "chmod 755 $FRIDA_SERVER_PATH; $FRIDA_SERVER_PATH -D >/dev/null 2>&1 &" 2>$null | Out-Null } catch {}
        Start-Sleep -Seconds 2
        $fs_pid = try { (& $ADB -s $script:DEVICE shell "pidof frida-server" 2>$null) -join "" } catch { "" }
        $fs_pid = $fs_pid.Trim()
        if (-not $fs_pid) {
            Stop-WithError "Não foi possível iniciar o frida-server em $FRIDA_SERVER_PATH"
        }
    }
    Write-Ok "frida-server em execução como root (PID $fs_pid)"

    # Verificar module.apk (envia automaticamente se presente na pasta local)
    $mod_exists = try { (& $ADB -s $script:DEVICE shell "test -f $MODULE_APK_DEVICE && echo 1" 2>$null) -join "" } catch { "" }
    if ($mod_exists.Trim() -ne "1") {
        $local_mod = Join-Path $SCRIPT_DIR "module.apk"
        if (Test-Path -LiteralPath $local_mod -PathType Leaf) {
            Write-Log "module.apk não encontrado no dispositivo. Enviando $local_mod para $MODULE_APK_DEVICE..."
            try { & $ADB -s $script:DEVICE push $local_mod $MODULE_APK_DEVICE *>$null } catch {}
        }
    }

    try { & $ADB -s $script:DEVICE shell "ls $MODULE_APK_DEVICE" *>$null } catch {}
    if ($LASTEXITCODE -ne 0) {
        Stop-WithError "module.apk não encontrado em $MODULE_APK_DEVICE no dispositivo. Envie-o primeiro:`n  adb -s $script:DEVICE push module.apk $MODULE_APK_DEVICE"
    }
    Write-Ok "module.apk presente"
}

# ===== 3. Obter PID do Google One =====
function Get-GoogleOnePid {
    $pkgPath = try { (& $ADB -s $script:DEVICE shell "pm path $GOOGLE_ONE_PKG" 2>$null) -join "" } catch { "" }
    if (-not $pkgPath.Trim()) {
        Stop-WithError "Google One ($GOOGLE_ONE_PKG) não está instalado neste dispositivo. Instale pela Play Store primeiro."
    }

    Write-Log "Reiniciando Google One para estado limpo..."
    try { & $ADB -s $script:DEVICE shell "am force-stop $GOOGLE_ONE_PKG" 2>$null | Out-Null } catch {}
    Start-Sleep -Seconds 1
    try { & $ADB -s $script:DEVICE shell "monkey -p $GOOGLE_ONE_PKG 1" *>$null } catch {}
    Start-Sleep -Seconds 3

    $raw_pid = try { (& $ADB -s $script:DEVICE shell "pidof $GOOGLE_ONE_PKG" 2>$null) -join " " } catch { "" }
    $raw_pid = $raw_pid.Trim()
    if (-not $raw_pid) {
        Stop-WithError "Não foi possível iniciar o Google One"
    }
    # pidof pode retornar múltiplos PIDs; pega o primeiro
    $g1_pid = ($raw_pid -split '\s+')[0]
    Write-Ok "PID do Google One: $g1_pid"
    return $g1_pid
}

function Write-WebCheckoutHtml([string]$outPath, $items) {
    $offersForJs = [System.Collections.Generic.List[psobject]]::new()
    foreach ($it in $items) {
        if (-not $it.offerToken) { continue }
        $p0 = if ($it.phases -and $it.phases.Count -gt 0) { $it.phases[0].formattedPrice } else { "" }
        $p1 = if ($it.phases -and $it.phases.Count -gt 1) { $it.phases[1].formattedPrice } else { "" }
        $offersForJs.Add([pscustomobject]@{
            sku      = [string]$it.product
            title    = [string]$it.title
            offerId  = [string]$it.offerId
            basePlan = [string]$it.basePlanId
            isTrial  = [bool]$it.isTrial
            isPromo  = [bool]$it.isPromo
            days     = [int]$it.days
            months   = [int]$it.months
            p0       = [string]$p0
            p1       = [string]$p1
            token    = [string]$it.offerToken
        })
    }
    # Incluir tokens extras do Ultra (google-ultra) para teste direto no navegador
    $offersForJs.Add([pscustomobject]@{
        sku = "g1.play.20tb"; title = "Google AI Ultra (20 TB) — Token Extra"; offerId = "ultra-20tb-12m"; basePlan = "monthly"
        isTrial = $true; isPromo = $false; days = 365; months = 12; p0 = "Grátis"; p1 = "Ultra 20TB"; token = "AYrTWi65Jbm3KRubLXLLA3Re29zKibSnRbvAJEPfxEIVs/d57w8vEhsU7hSkSAfGyjZH8B7/5aj5UTlidbsEwUH8aPN2RTA6pKiltA=="
    })
    $offersForJs.Add([pscustomobject]@{
        sku = "g1.play.ai.pro"; title = "Google AI Ultra (30 TB) — Token Extra"; offerId = "ultra-30tb-1m"; basePlan = "monthly"
        isTrial = $true; isPromo = $false; days = 30; months = 1; p0 = "Grátis"; p1 = "Ultra 30TB"; token = "AYrTWi7nBQ2Zn0z4s+QJOwg9kQRwH3+z+HXpzRqw9IIU4/C48vPvjH32Bub8SHrWq3YX+yI4g1wJgviYiLCobJNqc9DqRd9WZnDdaQ=="
    })
    $offersJson = $offersForJs | ConvertTo-Json -Depth 5 -Compress

    $html = @"
<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Google One / AI — Testador de Ofertas Web</title>
<style>
  body { font-family: system-ui, -apple-system, sans-serif; background:#0f1117; color:#e6edf3; margin:0; padding:24px; }
  .wrap { max-width:920px; margin:0 auto; }
  h1 { font-size:20px; margin:0 0 8px; }
  .bar { display:flex; gap:12px; align-items:center; flex-wrap:wrap; margin:16px 0; padding:12px; background:#161b22; border:1px solid #30363d; border-radius:8px; }
  select, input { background:#0d1117; color:#e6edf3; border:1px solid #30363d; border-radius:6px; padding:6px 10px; }
  .grid { display:grid; grid-template-columns:repeat(auto-fill,minmax(270px,1fr)); gap:12px; }
  .card { background:#161b22; border:1px solid #30363d; border-radius:8px; padding:14px; display:flex; flex-direction:column; gap:6px; }
  .card.trial { border-color:#238636; }
  .sku { font-family:monospace; font-size:12px; color:#8b949e; }
  .badge { display:inline-block; font-size:11px; padding:2px 7px; border-radius:12px; background:#238636; color:#fff; width:fit-content; }
  .badge.std { background:#30363d; color:#c9d1d9; }
  button { margin-top:auto; padding:8px 12px; border:0; border-radius:6px; background:#2f81f7; color:#fff; font-weight:600; cursor:pointer; }
  button:hover { background:#388bfd; }
</style>
</head>
<body>
<div class="wrap">
  <h1>Google One / AI — Checkout Web Direto</h1>
  <div class="bar">
    <label>Conta Google (authuser):
      <select id="authuser">
        <option value="0">0 (principal)</option>
        <option value="1">1</option>
        <option value="2">2</option>
        <option value="3">3</option>
        <option value="4">4</option>
      </select>
    </label>
    <label><input type="checkbox" id="onlyTrials" checked> Só trials / promos grátis</label>
    <label><input type="checkbox" id="legacy"> Modo compatibilidade</label>
  </div>
  <div class="grid" id="grid"></div>
</div>
<script>
const FP_TEMPLATE = "W1tudWxsLG51bGwsbnVsbCxbbnVsbCxbIlJzMi4wLjY6OjpzMTExLDIsMjZiNWUxOSwwLDc2OSxhMDYzZWJlOSwwLDRhMixlZGQ5OGJhYywwLDE4LDQ4NjNmZDM1LDAsNzY5LGNiMmQ1YzZmLDAsNDdlLDZhZDQ3YzZjLDAsNTNlLDdiZGI0OWY2LDAsNDI4LGI2NTQwMjAwLDAsNzY5LGVlYTgyMGI2LDAsNDdlLDFhYTQzMzEsMCxcIldpbjMyLGY1NDY4M2YyLDAsXCJHb29nbGUgSW5jLixhZjc5NDUxNSwwLFwiNS4wIDI4V2luZG93cyBOVCAxMC4wM2IgV2luNjQzYiB4NjQyOSBBcHBsZVdlYktpdDJmNTM3LjM2IDI4S0hUTUwyYyBsaWtlIEdlY2tvMjkgQ2hyb21lMmYxMjUuMC4wLjAgU2FmYXJpMmY1MzcuMzYsZDgxNzIzZDEsMCxcImVuMmRVUyw1Y2MzYWI1ZiwwLFwiTW96aWxsYTJmNS4wIDI4V2luZG93cyBOVCAxMC4wM2IgV2luNjQzYiB4NjQyOSBBcHBsZVdlYktpdDJmNTM3LjM2IDI4S0hUTUwyYyBsaWtlIEdlY2tvMjkgQ2hyb21lMmYxMjUuMC4wLjAgU2FmYXJpMmY1MzcuMzYsMjRhNjZkZjYsMCwxMmMsXCJXZWQgRGVjIDMxIDE5NjkgMTlhMDAzYTAwIEdNVDJkMDUwMCAyOEVhc3Rlcm4gU3RhbmRhcmQgVGltZTI5LDJjYTA1NTRmLFwiUERGIFZpZXdlciwwLFwiUG9ydGFibGUgRG9jdW1lbnQgRm9ybWF0LFwiQ2hyb21lIFBERiBWaWV3ZXIsMCxcIlBvcnRhYmxlIERvY3VtZW50IEZvcm1hdCxcIkNocm9taXVtIFBERiBWaWV3ZXIsMCxcIlBvcnRhYmxlIERvY3VtZW50IEZvcm1hdCxcIk1pY3Jvc29mdCBFZGdlIFBERiBWaWV3ZXIsMCxcIlBvcnRhYmxlIERvY3VtZW50IEZvcm1hdCxcIldlYktpdCBidWlsdDJkaW4gUERGLDAsXCJQb3J0YWJsZSBEb2N1bWVudCBGb3JtYXQsNmM4YjlkNWIsNzcwYzY3ZmMsMCwwOmEyMSwzLDFhMWRkYzkzMmQ0LDAsODQsMTphNDAsXCJmLDFhMWRkYzkzMmQ1Il0sIk1vemlsbGEvNS4wIChXaW5kb3dzIE5UIDEwLjA7IFdpbjY0OyB4NjQpIEFwcGxlV2ViS2l0LzUzNy4zNiAoS0hUTUwsIGxpa2UgR2Vja28pIENocm9tZS8xMjUuMC4wLjAgU2FmYXJpLzUzNy4zNiIsImh0dHBzOi8vcGF5bWVudHMuZ29vZ2xlLmNvbSJdLG51bGwsbnVsbCwiZW4iLDEsMV0sWyJodHRwczovL3BheW1lbnRzLmdvb2dsZS5jb20vcGF5bWVudHMvcmVkaXJlY3RfZm9ybV9sYW5kaW5nP3N1Y2Nlc3M9dHJ1ZSIsImh0dHBzOi8vcGF5bWVudHMuZ29vZ2xlLmNvbS9wYXltZW50cy9yZWRpcmVjdF9mb3JtX2xhbmRpbmc/c3VjY2Vzcz1mYWxzZSJdXQ==";
const PATH = "/plans?g1_last_touchpoint=37&g1_landing_page=1&otzr=1";
const OFFERS = $offersJson;

function enc(s) {
  return s.replace(/\//g,"2f").replace(/-/g,"2d").replace(/;/g,"3b").replace(/\(/g,"28").replace(/\)/g,"29").replace(/,/g,"2c").replace(/:/g,"3a");
}
function buildFp() {
  try {
    let s = atob(FP_TEMPLATE);
    const ua = navigator.userAgent;
    const plat = /Mac/.test(navigator.platform) ? "MacIntel" : /Win/.test(navigator.platform) ? "Win32" : (navigator.platform || "Linux x86_64");
    s = s.split("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36").join(ua);
    s = s.split('\\"Win32').join('\\"' + plat);
    s = s.split("5.0 28Windows NT 10.03b Win643b x6429 AppleWebKit2f537.36 28KHTML2c like Gecko29 Chrome2f125.0.0.0 Safari2f537.36").join(enc(ua.replace(/^Mozilla\//, "")));
    s = s.split("Wed Dec 31 1969 193a003a00 GMT2d0500 28Eastern Standard Time29").join(enc(new Date(0).toString()));
    s = s.split('"en",1,1').join('"' + (navigator.language || "pt-BR") + '",1,1');
    return btoa(s);
  } catch (e) { return FP_TEMPLATE; }
}
function openCheckout(offer) {
  const auth = document.getElementById("authuser").value;
  const legacy = document.getElementById("legacy").checked;
  const fp = legacy ? FP_TEMPLATE : buildFp();
  const item = [["subs:com.google.android.apps.subscriptions.red:" + offer.sku, 21], null, null, null, 1, [offer.token]];
  const ear = new Array(25).fill(null);
  ear[2] = [null, null, PATH];
  ear[4] = [fp];
  ear[13] = [[item]];
  ear[21] = 1;
  const id = "I0_" + Date.now();
  const gapi = "&usegapi=1&id=" + id + "&_gfid=" + id + "&parent=https%3A%2F%2Fone.google.com&pfname=&rpctoken=" + (1000000 + Math.floor(Math.random() * 8000000)) + "&jsh=" + encodeURIComponent("m;/_/scs/abc-static/_/js/k=gapi.lb.pt_BR.O/d=1/rs=AHpOoo/m=__features__");
  const url = "https://tokenized.play.google.com/eacquire/multiline?authuser=" + encodeURIComponent(auth) + "&ear=" + encodeURIComponent(JSON.stringify(ear)) + gapi;
  window.open(url, "_blank");
}
function render() {
  const onlyTrials = document.getElementById("onlyTrials").checked;
  const grid = document.getElementById("grid");
  grid.innerHTML = "";
  OFFERS.filter(o => !onlyTrials || o.isTrial || o.isPromo).forEach(o => {
    const div = document.createElement("div");
    div.className = "card" + (o.isTrial ? " trial" : "");
    div.innerHTML = '<span class="badge ' + (o.isTrial ? '' : 'std') + '">' + (o.isTrial ? (o.months + 'm grátis (' + o.days + 'd)') : (o.p0 || 'Padrão')) + '</span>'
      + '<strong>' + o.title + '</strong>'
      + '<div class="sku">' + o.sku + ' · ' + (o.offerId || o.basePlan) + '</div>'
      + '<div class="sku">' + o.p0 + (o.p1 ? ' -> ' + o.p1 : '') + '</div>';
    const btn = document.createElement("button");
    btn.textContent = "Abrir Checkout Web";
    btn.onclick = () => openCheckout(o);
    div.appendChild(btn);
    grid.appendChild(div);
  });
}
document.getElementById("onlyTrials").onchange = render;
render();
</script>
</body>
</html>
"@
    [System.IO.File]::WriteAllText($outPath, $html, (New-Object System.Text.UTF8Encoding($false)))
}

function Get-PurchaseTokenFromLibraryDb([string]$skuHint = "g1.") {
    $remoteDb = "/data/local/tmp/lib_read_$PID.db"
    $localDb = Join-Path ([System.IO.Path]::GetTempPath()) "lib_read_$PID.db"
    try {
        try { & $ADB -s $script:DEVICE shell "cp /data/data/com.android.vending/databases/library.db $remoteDb 2>/dev/null; chmod 666 $remoteDb" 2>$null | Out-Null } catch {}
        if (Test-Path -LiteralPath $localDb) { Remove-Item -LiteralPath $localDb -Force -ErrorAction SilentlyContinue }
        try { & $ADB -s $script:DEVICE pull $remoteDb $localDb 2>$null | Out-Null } catch {}
        try { & $ADB -s $script:DEVICE shell "rm -f $remoteDb" 2>$null | Out-Null } catch {}
        if (-not (Test-Path -LiteralPath $localDb -PathType Leaf)) { return "" }

        $pyCmd = @'
import sqlite3, json, time, sys
db_path, hint = sys.argv[1], sys.argv[2]
con = sqlite3.connect(db_path)
rows = con.execute("SELECT account, doc_id, subs_valid_until_time, inapp_purchase_data FROM ownership WHERE doc_id LIKE ?", (f"%{hint}%",)).fetchall()
now_ms = int(time.time() * 1000)
picked = None
for acc, doc_id, valid, data in rows:
    if not data: continue
    try: j = json.loads(data)
    except Exception: continue
    tk = j.get("purchaseToken")
    if not tk: continue
    try: alive = int(valid) > now_ms
    except Exception: alive = False
    v = int(valid or 0)
    if picked is None or (alive and not picked[2]) or (alive == picked[2] and v > picked[3]):
        picked = (tk, acc, alive, v, doc_id)
if picked:
    print(f"{picked[0]}|{picked[1]}|{picked[2]}|{picked[4]}")
'@
        $out = try { (& python -c $pyCmd $localDb $skuHint 2>$null) -join "" } catch { "" }
        $out = $out.Trim()
        if ($out -and $out.Contains("|")) {
            $parts = $out -split '\|', 4
            Write-Ok "purchaseToken lido de library.db ($($parts[1]), ativo=$($parts[2]), doc=$($parts[3]))"
            return $parts[0]
        }
    } finally {
        if (Test-Path -LiteralPath $localDb) { Remove-Item -LiteralPath $localDb -Force -ErrorAction SilentlyContinue }
    }
    return ""
}

# ===== 4. Aplicar configurações e executar script Frida =====
function Invoke-Frida($g1_pid, [string]$runMode, [string]$runTarget, [string]$runDuration, [string]$runOffer, [string]$fridaBin) {
    $tmp_script = Join-Path ([System.IO.Path]::GetTempPath()) ".frida-run-$PID.js"
    $frida_proc = $null
    $discovered_trials = [System.Collections.Generic.List[psobject]]::new()
    $export_items = [System.Collections.Generic.List[psobject]]::new()

    try {
        $resolvedOldTok = $OLD_PURCHASE_TOKEN
        if ($UPGRADE_MODE -and -not $resolvedOldTok -and $runMode -eq "activate") {
            Write-Log "Lendo purchaseToken ativo de library.db..."
            $resolvedOldTok = Get-PurchaseTokenFromLibraryDb "g1."
            if (-not $resolvedOldTok) {
                Write-Warn "Nenhum purchaseToken encontrado em library.db; tentando queryPurchasesAsync..."
            }
        }

        # Aplicar configuração no script com escape seguro
        $content = Get-Content -LiteralPath $FRIDA_SCRIPT -Raw -Encoding UTF8
        $jsMode    = ConvertTo-JsStringLiteral $runMode
        $jsTarget  = ConvertTo-JsStringLiteral $runTarget
        $jsOffer   = ConvertTo-JsStringLiteral $runOffer
        $jsDur     = ConvertTo-JsStringLiteral $runDuration
        $jsApk     = ConvertTo-JsStringLiteral $MODULE_APK_DEVICE
        $jsExtra   = ConvertTo-JsStringLiteral $EXTRA_PRODUCTS
        $jsOldTok  = ConvertTo-JsStringLiteral $resolvedOldTok
        $jsPromos  = if ($INCLUDE_PROMOS) { "true" } else { "false" }
        $jsUpgrade = if ($UPGRADE_MODE) { "true" } else { "false" }
        $content = [regex]::Replace($content, '(?m)^var MODE = .*', { param($m) "var MODE = $jsMode;" })
        $content = [regex]::Replace($content, '(?m)^var TARGET_PRODUCT = .*', { param($m) "var TARGET_PRODUCT = $jsTarget;" })
        $content = [regex]::Replace($content, '(?m)^var TARGET_OFFER = .*', { param($m) "var TARGET_OFFER = $jsOffer;" })
        $content = [regex]::Replace($content, '(?m)^var PREFER_DURATION = .*', { param($m) "var PREFER_DURATION = $jsDur;" })
        $content = [regex]::Replace($content, '(?m)^var MODULE_APK = .*', { param($m) "var MODULE_APK = $jsApk;" })
        $content = [regex]::Replace($content, '(?m)^var EXTRA_PRODUCTS = .*', { param($m) "var EXTRA_PRODUCTS = $jsExtra;" })
        $content = [regex]::Replace($content, '(?m)^var INCLUDE_PROMOS = .*', { param($m) "var INCLUDE_PROMOS = $jsPromos;" })
        $content = [regex]::Replace($content, '(?m)^var UPGRADE_MODE = .*', { param($m) "var UPGRADE_MODE = $jsUpgrade;" })
        $content = [regex]::Replace($content, '(?m)^var OLD_PURCHASE_TOKEN = .*', { param($m) "var OLD_PURCHASE_TOKEN = $jsOldTok;" })
        $content = [regex]::Replace($content, '(?m)^var REPLACE_MODE = .*', { param($m) "var REPLACE_MODE = $REPLACE_MODE;" })
        [System.IO.File]::WriteAllText($tmp_script, $content, (New-Object System.Text.UTF8Encoding($false)))

        Write-Log "Injetando (modo=$runMode alvo=$runTarget oferta=$runOffer duração=$runDuration)..."

        # Limpar logcat ANTES da injeção para não perder saídas iniciais
        try { & $ADB -s $script:DEVICE logcat -c 2>$null | Out-Null } catch {}

        # Executar frida em segundo plano mantendo stdin aberto para o REPL não encerrar imediatamente
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $fridaBin
        $psi.Arguments = "-H 127.0.0.1:$($script:FRIDA_LOCAL_PORT) -p $g1_pid -l `"$tmp_script`" -q -t $($WAIT_TIMEOUT + 30)"
        $psi.UseShellExecute = $false
        $psi.RedirectStandardInput = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        $frida_proc = [System.Diagnostics.Process]::Start($psi)

        # Consultar logcat em loop
        Write-Log "Aguardando resultados..."
        $elapsed = 0
        $max_wait = if ($runMode -eq "sniff") { $WAIT_TIMEOUT } elseif ($runMode -eq "discover") { 120 } else { 60 }
        $got_terminal = $false
        $flow_launched = $false
        $seen_lines = 0

        while ($elapsed -lt $max_wait) {
            Start-Sleep -Seconds 1
            $elapsed += 1

            if ($frida_proc.HasExited -and $seen_lines -eq 0) {
                $frida_out = ($frida_proc.StandardOutput.ReadToEnd() + "`n" + $frida_proc.StandardError.ReadToEnd()).Trim()
                if ($frida_out) {
                    Write-Err "Frida encerrou com erro:`n$frida_out"
                    $got_terminal = $true
                    break
                }
            }

            $raw_lines = try { & $ADB -s $script:DEVICE logcat -d -s "AutoTrial:*" 2>$null } catch { @() }
            if (-not $raw_lines) { continue }

            $lines = @()
            foreach ($line in $raw_lines) {
                if ($line -match 'AutoTrial\s*: (.*)$') {
                    $lines += $Matches[1].TrimEnd("`r")
                }
            }

            $total_lines = $lines.Count
            if ($total_lines -le $seen_lines) { continue }

            $new_lines = $lines[$seen_lines..($total_lines - 1)]
            $seen_lines = $total_lines

            foreach ($msg in $new_lines) {
                if ($msg -like "=== AUTO_TRIAL_START*") { Write-Log "Script iniciado" }
                elseif ($msg -eq "=== SNIFF_READY ===") {
                    Write-Ok "Sniff ativo (${WAIT_TIMEOUT}s) — navegue pelas telas de planos/ofertas no Google One (Ctrl-C para parar)"
                }
                elseif ($msg -like "SNIFF_QUERY *") { Write-Ok $msg }
                elseif ($msg -like "SNIFF_FLOW *") { Write-Ok $msg }
                elseif ($msg -eq "BillingClient connected") { Write-Ok "BillingClient conectado" }
                elseif ($msg -like "Discover matrix size:*") { Write-Log $msg }
                elseif ($msg -like "ACTIVE_SUBS *") { Write-Warn "Conta já possui assinatura ativa ($msg)" }
                elseif ($msg -like "  ACTIVE_SUB:*") { Write-Warn $msg }
                elseif ($msg -like "Products found:*") { Write-Log $msg }
                elseif ($msg -like "PRODUCT*") { Write-Host ""; Write-Host "  $msg" }
                elseif ($msg.StartsWith("  [")) { Write-Host "    $msg" }
                elseif ($msg -like "  TRIAL *") {
                    Write-Ok $msg
                    if ($msg -match '^\s*TRIAL\s+(\S+)\s+/\s+(\S+)\s+—\s+(\d+)\s+meses') {
                        $discovered_trials.Add([pscustomobject]@{
                            Product = $Matches[1]
                            OfferId = $Matches[2]
                            Months  = [int]$Matches[3]
                            DurArg  = "$($Matches[3])mo"
                        })
                    }
                }
                elseif ($msg -like "TRIALS_FOUND*") { Write-Host ""; Write-Log $msg }
                elseif ($msg -like "PROMOS_FOUND*") { Write-Log $msg }
                elseif ($msg -like "  PROMO *") { Write-Warn $msg }
                elseif ($msg -like "JSON_EXPORT_ITEM *") {
                    if ($EXPORT_PATH -or $WEB_OUT) {
                        $rawJson = $msg.Substring("JSON_EXPORT_ITEM ".Length)
                        try { $export_items.Add(($rawJson | ConvertFrom-Json)) } catch {}
                    }
                }
                elseif ($msg -like "SELECTED*") { Write-Ok $msg }
                elseif ($msg -like "Waiting for Activity*") { Write-Log "Estabilizando Activity..." }
                elseif ($msg -like "UPGRADE_PARAMS_ATTACHED*") { Write-Log $msg }
                elseif ($msg -like "BILLING_FLOW_LAUNCHED*") {
                    Write-Ok "Janela de pagamento aberta — confirme ou cancele no emulador (aguardando resultado até ${WAIT_TIMEOUT}s)..."
                    $flow_launched = $true
                    $max_wait = [Math]::Max($max_wait, $elapsed + $WAIT_TIMEOUT)
                }
                elseif ($msg -eq "=== TRIAL_ACTIVATED ===") {
                    Write-Host ""
                    Write-Ok "AVALIAÇÃO ATIVADA COM SUCESSO"
                    Write-Host ""
                    Write-Host "  Renova automaticamente após a avaliação. Cancele antes do vencimento."
                    Write-Host ""
                    $got_terminal = $true
                }
                elseif ($msg -eq "=== USER_CANCELLED ===") {
                    Write-Err "Cancelado pelo usuário"
                    $got_terminal = $true
                }
                elseif ($msg -eq "=== ITEM_ALREADY_OWNED ===") {
                    Write-Err "Já possui assinatura"
                    $got_terminal = $true
                }
                elseif ($msg -like "=== PURCHASE_FAILED*") {
                    Write-Err $msg
                    $got_terminal = $true
                }
                elseif ($msg -eq "=== LIST_COMPLETE ===") {
                    Write-Host ""
                    Write-Ok "Listagem concluída"
                    $got_terminal = $true
                }
                elseif ($msg -eq "=== NO_TRIALS ===") {
                    Write-Err "Nenhuma oferta de avaliação encontrada"
                    $got_terminal = $true
                }
                elseif ($msg -eq "=== SELECT_FAILED ===" -or $msg -eq "=== NO_ACTIVITY ===" -or $msg -like "=== CONNECT_FAILED*" -or $msg -like "=== LAUNCH_ERROR*") {
                    Write-Err $msg
                    $got_terminal = $true
                }
            }

            if ($got_terminal) { break }
        }

        if (-not $got_terminal) {
            if ($flow_launched) {
                Write-Warn "Tempo esgotado (${WAIT_TIMEOUT}s) aguardando confirmação na janela de pagamento."
            } else {
                Write-Err "Tempo esgotado após ${max_wait}s — verifique o logcat manualmente: adb logcat -d -s AutoTrial:*"
            }
        }
        if ($EXPORT_PATH -and $export_items.Count -gt 0) {
            try {
                $jsonOut = $export_items | ConvertTo-Json -Depth 10
                [System.IO.File]::WriteAllText($EXPORT_PATH, $jsonOut, (New-Object System.Text.UTF8Encoding($false)))
                Write-Ok "Análise exportada para: $EXPORT_PATH ($($export_items.Count) ofertas)"
            } catch {
                Write-Warn "Falha ao salvar exportação em ${EXPORT_PATH}: $_"
            }
        }
        if ($WEB_OUT -and $export_items.Count -gt 0) {
            try {
                Write-WebCheckoutHtml $WEB_OUT $export_items
                Write-Ok "Página de checkout web gerada em: $WEB_OUT"
            } catch {
                Write-Warn "Falha ao gerar checkout web em ${WEB_OUT}: $_"
            }
        }
    } finally {
        if ($frida_proc -and -not $frida_proc.HasExited) {
            try { Stop-Process -Id $frida_proc.Id -Force -ErrorAction SilentlyContinue } catch {}
        }
        if (Test-Path -LiteralPath $tmp_script) {
            Remove-Item -LiteralPath $tmp_script -Force -ErrorAction SilentlyContinue
        }
    }

    return ,$discovered_trials
}

# ===== Principal =====
Write-Host "=== Google AI Trial Tool ==="
Write-Host ""

if (-not (Test-Path -LiteralPath $FRIDA_SCRIPT -PathType Leaf)) {
    Stop-WithError "Script Frida não encontrado: $FRIDA_SCRIPT"
}

$FRIDA_BIN = Find-Frida
if (-not $FRIDA_BIN) {
    Stop-WithError "frida CLI não encontrado. Instale com: pip install frida==16.7.19 `"frida-tools<14.0.0`""
}
Test-FridaVersion $FRIDA_BIN

Find-Device

$UI_TEXT = @{
    pt = @{
        menu_title = "Menu Principal"
        opt1       = "[1] Listar e escolher avaliação (--list)"
        opt2       = "[2] Buscar novos planos e escolher (--discover)"
        opt3       = "[3] Ativar Pro 12 meses direto (pro12 12mo)"
        opt4       = "[4] Gerar página checkout web (checkout.html)"
        opt5       = "[5] Sniff em tempo real (--sniff)"
        opt0       = "[0] Sair"
        prompt     = "Opção (0-5)"
        invalid    = "Opção inválida"
        pick_title = "Escolha a avaliação para ativar"
        pick_back  = "[0] Voltar ao menu"
        pick_ask   = "Escolha"
        activating = "Ativando"
        months     = "meses grátis"
    }
    en = @{
        menu_title = "Main Menu"
        opt1       = "[1] List and pick free trial (--list)"
        opt2       = "[2] Discover new plans and pick (--discover)"
        opt3       = "[3] Activate Pro 12 months directly (pro12 12mo)"
        opt4       = "[4] Generate web checkout page (checkout.html)"
        opt5       = "[5] Live SKU sniff (--sniff)"
        opt0       = "[0] Exit"
        prompt     = "Option (0-5)"
        invalid    = "Invalid option"
        pick_title = "Select trial to activate"
        pick_back  = "[0] Back to menu"
        pick_ask   = "Choice"
        activating = "Activating"
        months     = "months free"
    }
    zh = @{
        menu_title = "主菜单"
        opt1       = "[1] 列出并选择免费试用 (--list)"
        opt2       = "[2] 探测更多方案并选择 (--discover)"
        opt3       = "[3] 直接激活 Pro 12 个月 (pro12 12mo)"
        opt4       = "[4] 生成网页结账页 (checkout.html)"
        opt5       = "[5] 实时抓包 SKU (--sniff)"
        opt0       = "[0] 退出"
        prompt     = "选项 (0-5)"
        invalid    = "无效选项"
        pick_title = "选择要激活的试用方案"
        pick_back  = "[0] 返回主菜单"
        pick_ask   = "选择"
        activating = "正在激活"
        months     = "个月免费"
    }
}

function Invoke-MenuSession {
    if (-not $LANG_EXPLICIT) {
        Write-Host "Idioma / Language / 语言:" -ForegroundColor Cyan
        Write-Host "  [1] Português (Brasil)"
        Write-Host "  [2] English"
        Write-Host "  [3] 简体中文 (Chinese)"
        Write-Host ""
        $langPick = Read-Host "Escolha / Choice / 选择 (1-3, padrão 1)"
        switch ($langPick) {
            "2" { $script:UI_LANG = "en" }
            "3" { $script:UI_LANG = "zh" }
            default { $script:UI_LANG = "pt" }
        }
    }
    $t = $UI_TEXT[$script:UI_LANG]
    while ($true) {
        Write-Host ""
        Write-Host "=== $($t.menu_title) ($($script:DEVICE)) ===" -ForegroundColor Cyan
        Write-Host "  $($t.opt1)"
        Write-Host "  $($t.opt2)"
        Write-Host "  $($t.opt3)"
        Write-Host "  $($t.opt4)"
        Write-Host "  $($t.opt5)"
        Write-Host "  $($t.opt0)"
        Write-Host ""
        $menuPick = Read-Host $t.prompt

        $runMode = "list"
        $runTarget = "auto"
        $runDur = "longest"
        $runOffer = ""
        $askPick = $false
        $script:WEB_OUT = ""

        switch ($menuPick) {
            "1" { $runMode = "list"; $askPick = $true }
            "2" { $runMode = "discover"; $askPick = $true }
            "3" { $runMode = "activate"; $runTarget = "g1.2tb.ai.subs_variant"; $runDur = "12mo" }
            "4" { $runMode = "discover"; $script:WEB_OUT = Join-Path $SCRIPT_DIR "checkout.html" }
            "5" { $runMode = "sniff" }
            "0" { return }
            default { Write-Warn "$($t.invalid): $menuPick"; continue }
        }

        Write-Host ""
        $g1_pid = Get-GoogleOnePid
        Write-Host ""
        $trials = Invoke-Frida $g1_pid $runMode $runTarget $runDur $runOffer $FRIDA_BIN

        if ($askPick -and $trials -and $trials.Count -gt 0) {
            Write-Host ""
            Write-Host "=== $($t.pick_title) ===" -ForegroundColor Cyan
            for ($idx = 0; $idx -lt $trials.Count; $idx++) {
                $tr = $trials[$idx]
                Write-Host ("  [{0}] {1} ({2}) — {3} {4}" -f ($idx + 1), $tr.Product, $tr.OfferId, $tr.Months, $t.months)
            }
            Write-Host "  $($t.pick_back)"
            Write-Host ""

            $choiceRaw = Read-Host "$($t.pick_ask) (0-$($trials.Count))"
            $choice = 0
            if ([int]::TryParse($choiceRaw, [ref]$choice) -and $choice -ge 1 -and $choice -le $trials.Count) {
                $picked = $trials[$choice - 1]
                Write-Host ""
                Write-Ok "$($t.activating): $($picked.Product) / $($picked.OfferId) ($($picked.DurArg))..."
                $g1_pid2 = Get-GoogleOnePid
                Write-Host ""
                $null = Invoke-Frida $g1_pid2 "activate" $picked.Product $picked.DurArg $picked.OfferId $FRIDA_BIN
            }
        }
    }
}

try {
    Initialize-Frida

    if ($SHOW_MENU) {
        Invoke-MenuSession
    } else {
        $g1_pid = Get-GoogleOnePid

        Write-Host ""
        $trials = Invoke-Frida $g1_pid $MODE $TARGET $DURATION $TARGET_OFFER $FRIDA_BIN

        if ($INTERACTIVE -and $trials -and $trials.Count -gt 0) {
            Write-Host ""
            Write-Host "=== Selecione a avaliação para ativar ===" -ForegroundColor Cyan
            for ($idx = 0; $idx -lt $trials.Count; $idx++) {
                $t = $trials[$idx]
                Write-Host ("  [{0}] {1} ({2}) — {3} meses grátis" -f ($idx + 1), $t.Product, $t.OfferId, $t.Months)
            }
            Write-Host "  [0] Sair"
            Write-Host ""

            $choiceRaw = Read-Host "Escolha (0-$($trials.Count))"
            $choice = 0
            if ([int]::TryParse($choiceRaw, [ref]$choice) -and $choice -ge 1 -and $choice -le $trials.Count) {
                $picked = $trials[$choice - 1]
                Write-Host ""
                Write-Ok "Ativando: $($picked.Product) / $($picked.OfferId) ($($picked.DurArg))..."
                $g1_pid2 = Get-GoogleOnePid
                Write-Host ""
                $null = Invoke-Frida $g1_pid2 "activate" $picked.Product $picked.DurArg $picked.OfferId $FRIDA_BIN
            } elseif ($choice -ne 0) {
                Write-Warn "Opção inválida; encerrando."
            }
        }
    }
} finally {
    if ($script:DEVICE -and $script:FRIDA_LOCAL_PORT) {
        try { & $ADB -s $script:DEVICE forward --remove "tcp:$($script:FRIDA_LOCAL_PORT)" 2>$null | Out-Null } catch {}
    }
}
