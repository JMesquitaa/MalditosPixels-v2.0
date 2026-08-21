# install.ps1 — Malditos Pixels v2.0
# Localiza o Assetto Corsa via registro do Steam e copia os arquivos.
# Execute com: .\install.ps1

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Find-AssettoCorsa {
    $appId = "244210"
    $regPaths = @(
        "HKLM:\SOFTWARE\Valve\Steam",
        "HKLM:\SOFTWARE\Wow6432Node\Valve\Steam",
        "HKCU:\SOFTWARE\Valve\Steam"
    )

    $steamPath = $null
    foreach ($rp in $regPaths) {
        try {
            $val = Get-ItemPropertyValue -Path $rp -Name "InstallPath" -ErrorAction SilentlyContinue
            if ($val -and (Test-Path $val)) { $steamPath = $val; break }
        } catch {}
    }
    if (-not $steamPath) { return $null }

    $libFile = Join-Path $steamPath "steamapps\libraryfolders.vdf"
    $candidates = @($steamPath)
    if (Test-Path $libFile) {
        Select-String -Path $libFile -Pattern '"path"\s+"([^"]+)"' |
            ForEach-Object { $candidates += $_.Matches[0].Groups[1].Value }
    }

    foreach ($lib in $candidates) {
        $ac = Join-Path $lib "steamapps\common\assettocorsa"
        if (Test-Path (Join-Path $ac "AssettoCorsa.exe")) { return $ac }
    }
    return $null
}

$acPath = Find-AssettoCorsa
if (-not $acPath) {
    Write-Host "Assetto Corsa nao encontrado automaticamente."
    $acPath = Read-Host "Informe o caminho completo da pasta do Assetto Corsa"
    if (-not (Test-Path (Join-Path $acPath "AssettoCorsa.exe"))) {
        Write-Error "Caminho invalido: AssettoCorsa.exe nao encontrado em '$acPath'."
    }
}

Write-Host "Assetto Corsa encontrado em: $acPath"

$src  = $PSScriptRoot
$pairs = @(
    @{ From = "system\cfg\ppfilters";                                      To = "system\cfg\ppfilters" },
    @{ From = "extension\config-ext\PureHdrEffects\MPIXELS_FX";           To = "extension\config-ext\PureHdrEffects\MPIXELS_FX" },
    @{ From = "extension\config-ext\PureLdrEffects\MPIXELS_FX_LDR";       To = "extension\config-ext\PureLdrEffects\MPIXELS_FX_LDR" },
    @{ From = "extension\textures\color_grading";                          To = "extension\textures\color_grading" }
)

foreach ($pair in $pairs) {
    $srcDir  = Join-Path $src $pair.From
    $destDir = Join-Path $acPath $pair.To
    if (-not (Test-Path $srcDir)) {
        Write-Warning "Origem nao encontrada, pulando: $srcDir"
        continue
    }
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null
    Copy-Item -Path "$srcDir\*" -Destination $destDir -Recurse -Force
    Write-Host "Copiado: $($pair.From) -> $destDir"
}

# Verificar se as 5 LUTs de color grading chegaram no destino
$luts = @(
    "mpixels_rachadores.png",
    "mpixels_cinema.png",
    "mpixels_puro.png",
    "mpixels_vivo.png",
    "mpixels_madrugada.png"
)
$lutDest = Join-Path $acPath "extension\textures\color_grading"
$faltando = @()
foreach ($lut in $luts) {
    $p = Join-Path $lutDest $lut
    if (-not (Test-Path $p)) { $faltando += $lut }
}
if ($faltando.Count -gt 0) {
    Write-Warning "LUTs de color grading NAO encontradas no destino. A cor vai sair errada (ceu chapado de dia)."
    Write-Warning "Faltando: $($faltando -join ', ')"
}

Write-Host ""
Write-Host "Instalacao concluida."
Write-Host "Selecione 'Malditos Pixels' no Content Manager > Video > Post-Processing Filter."
Write-Host ""
Write-Host "--- PASSOS MANUAIS ---"
Write-Host ""
Write-Host "1. Preset CSP: arraste 'csp-preset\MALDITOS PIXELS.ini' para dentro do Content Manager"
Write-Host "   em Settings > Custom Shaders Patch > Presets."
Write-Host ""
Write-Host "2. Skydomes (~292 MB): baixe em Releases no GitHub e extraia em:"
Write-Host "   $acPath\system\cfg\ppfilters\pure_scripts\textures\"
