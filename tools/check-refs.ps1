# check-refs.ps1
# Verifica se todos os arquivos referenciados nos .ini e .lua existem no repo.
# Uso: cd <raiz-do-repo> && powershell -File tools\check-refs.ps1

Set-StrictMode -Version Latest
$repoRoot = Split-Path -Parent $PSScriptRoot

$expectedMissing = @(
    "system/cfg/ppfilters/pure_scripts/textures/mpixels_milkyway.dds",
    "system/cfg/ppfilters/pure_scripts/textures/mpixels_aurora.dds",
    "system/cfg/ppfilters/pure_scripts/textures/mpixels_twilight.dds",
    "system/cfg/ppfilters/pure_scripts/textures/mpixels_starfield.dds",
    "system/cfg/ppfilters/pure_scripts/textures/mpixels_overcast.dds"
)

# Chave: caminho normalizado, valor: "arquivo_origem:linha"
$refs = @{}
# Mapa de diretorio de origem para cada referencia (para busca relativa)
$refDirs = @{}

Get-ChildItem -Path $repoRoot -Recurse -Include "*.ini" | ForEach-Object {
    $file = $_.FullName
    $fileDir = $_.DirectoryName
    $lineNum = 0
    Get-Content $file | ForEach-Object {
        $lineNum++
        if ($_ -match '^\s*FILE\s*=\s*(.+\.(?:png|dds|cube))\s*$') {
            $ref = $Matches[1].Trim()
            $refs[$ref] = "${file}:${lineNum}"
            $refDirs[$ref] = $fileDir
        }
    }
}

Get-ChildItem -Path $repoRoot -Recurse -Include "*.lua" | ForEach-Object {
    $file = $_.FullName
    $fileDir = $_.DirectoryName
    $lineNum = 0
    Get-Content $file | ForEach-Object {
        $lineNum++
        $found = [regex]::Matches($_, '[\"'']([^\s\"'']+\.(?:png|dds|cube))[\"'']')
        foreach ($m in $found) {
            $ref = $m.Groups[1].Value
            $refs[$ref] = "${file}:${lineNum}"
            $refDirs[$ref] = $fileDir
        }
    }
}

Write-Host ""
Write-Host "=== CHECK-REFS: referencias de arquivo no repo ==="
Write-Host ""

$okCount = 0
$faltaCount = 0
$faltaEsperada = 0

foreach ($ref in ($refs.Keys | Sort-Object)) {
    $normalized = $ref -replace '\\', '/'

    # 1. Tentar caminho absoluto a partir da raiz do repo
    $fullPath = Join-Path $repoRoot ($normalized -replace '/', '\')
    $exists = (Test-Path $fullPath)

    # 2. Se nao achou e nao tem separador de diretorio, tentar relativo ao arquivo que referencia
    if (-not $exists -and $normalized -notmatch '[/\\]') {
        $relPath = Join-Path $refDirs[$ref] $normalized
        $exists = (Test-Path $relPath)
    }

    if ($exists) {
        Write-Host "  OK    $normalized"
        $okCount++
    }
    else {
        $isExpected = $expectedMissing -contains $normalized
        if ($isExpected) {
            Write-Host "  FALTA $normalized  (esperado, vai pra Releases)"
            $faltaEsperada++
        }
        else {
            Write-Host "  FALTA $normalized  *** INESPERADO ***"
            Write-Host "        referenciado em: $($refs[$ref])"
            $faltaCount++
        }
    }
}

Write-Host ""
Write-Host "Resultado: $okCount OK, $faltaEsperada FALTA esperada, $faltaCount FALTA inesperada"

if ($faltaCount -gt 0) {
    Write-Host ""
    Write-Warning "$faltaCount referencias a arquivos que NAO existem no repo."
    exit 1
}

Write-Host ""
Write-Host "Tudo certo."
exit 0
