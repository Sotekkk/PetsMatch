# export_specs.ps1
# Génère SPECS_PETSMATCH.docx et SPECS_PETSMATCH.pdf depuis TASKS.md et CAHIER_DES_CHARGES.md
# Usage : .\export_specs.ps1
# Optionnel : .\export_specs.ps1 -OpenAfter   -> ouvre le Word après génération

param(
    [switch]$OpenAfter
)

Set-Location $PSScriptRoot

# Ferme Word s'il est ouvert (évite "fichier déjà ouvert")
Get-Process WINWORD -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
if (Get-Process WINWORD -ErrorAction SilentlyContinue) { Start-Sleep -Milliseconds 800 }

$today    = Get-Date -Format "dd/MM/yyyy"
$htmlPath = "$PSScriptRoot\SPECS_PETSMATCH.html"
$docxPath = "$PSScriptRoot\SPECS_PETSMATCH.docx"
$pdfPath  = "$PSScriptRoot\SPECS_PETSMATCH.pdf"

# ── Lecture des fichiers sources ──────────────────────────────────────────────
$cdc   = [System.IO.File]::ReadAllText("$PSScriptRoot\CAHIER_DES_CHARGES.md", [System.Text.Encoding]::UTF8)
$tasks = [System.IO.File]::ReadAllText("$PSScriptRoot\TASKS.md",              [System.Text.Encoding]::UTF8)

# ── Helpers : conversion Markdown → HTML basique ─────────────────────────────
function ConvertMd {
    param([string]$md)

    # Échappement HTML
    $md = $md -replace '&', '&amp;' `
               -replace '<', '&lt;'  `
               -replace '>', '&gt;'

    # Titres
    $md = $md -replace '(?m)^### (.+)$',   '<h3>$1</h3>'
    $md = $md -replace '(?m)^## (.+)$',    '<h2>$1</h2>'
    $md = $md -replace '(?m)^# (.+)$',     '<h1>$1</h1>'

    # Gras et italique
    $md = $md -replace '\*\*(.+?)\*\*', '<b>$1</b>'
    $md = $md -replace '\*(.+?)\*',     '<i>$1</i>'
    $md = $md -replace '`(.+?)`',       '<code>$1</code>'

    # Barré ~~texte~~ → grisé
    $md = $md -replace '~~(.+?)~~', '<span style="color:#aaa;text-decoration:line-through">$1</span>'

    # Tableaux Markdown → HTML
    $lines = $md -split "`n"
    $out   = [System.Text.StringBuilder]::new()
    $inTable = $false

    foreach ($line in $lines) {
        $trimmed = $line.Trim()

        if ($trimmed -match '^\|') {
            # Ligne séparatrice |---|---|
            if ($trimmed -match '^\|[\s\-\|:]+$') {
                if (-not $inTable) {
                    [void]$out.Append('<table>')
                    $inTable = $true
                }
                continue
            }

            # Ligne de données
            $cells = $trimmed -replace '^\||\|$', '' -split '\|'

            if (-not $inTable) {
                [void]$out.Append('<table>')
                $inTable = $true
                # Première ligne = en-tête
                [void]$out.Append('<tr>')
                foreach ($c in $cells) {
                    $cv = $c.Trim()
                    # Appliquer icône statut
                    $cv = ApplyStatus $cv
                    [void]$out.Append("<th>$cv</th>")
                }
                [void]$out.Append('</tr>')
            } else {
                [void]$out.Append('<tr>')
                foreach ($c in $cells) {
                    $cv = $c.Trim()
                    $cv = ApplyStatus $cv
                    [void]$out.Append("<td>$cv</td>")
                }
                [void]$out.Append('</tr>')
            }
        } else {
            if ($inTable) {
                [void]$out.Append('</table>')
                $inTable = $false
            }
            if ($trimmed -eq '' -or $trimmed -eq '---') {
                [void]$out.Append('<br>')
            } elseif ($trimmed -match '^&gt;') {
                $note = $trimmed -replace '^&gt;\s*', ''
                [void]$out.Append("<p class='note'>$note</p>")
            } elseif ($trimmed -match '^- \[ \]') {
                [void]$out.Append("<li class='todo'>☐ $($trimmed -replace '^- \[ \] ?','')</li>")
            } elseif ($trimmed -match '^- \[x\]') {
                [void]$out.Append("<li class='done'>☑ $($trimmed -replace '^- \[x\] ?','')</li>")
            } elseif ($trimmed -match '^- ') {
                [void]$out.Append("<li>$($trimmed -replace '^- ','')</li>")
            } else {
                if ($trimmed -ne '') {
                    [void]$out.Append("<p>$trimmed</p>")
                }
            }
        }
    }
    if ($inTable) { [void]$out.Append('</table>') }

    return $out.ToString()
}

function ApplyStatus {
    param([string]$text)
    $text = $text -replace [regex]::Escape('✅'), '<span class="ok">✅</span>'
    $text = $text -replace [regex]::Escape('🔶'), '<span class="partial">🔶</span>'
    $text = $text -replace [regex]::Escape('⬜'), '<span class="todo">⬜</span>'
    return $text
}

# ── Construction du HTML ──────────────────────────────────────────────────────
$cdcHtml   = ConvertMd $cdc
$tasksHtml = ConvertMd $tasks

$html = @"
<!DOCTYPE html>
<html lang="fr">
<head>
<meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
<meta charset="UTF-8">
<style>
  body  { font-family: Calibri, Arial, sans-serif; font-size: 11pt; color: #1a1a1a; margin: 40px; }
  h1    { font-size: 20pt; color: #2c5f2e; border-bottom: 3px solid #2c5f2e; padding-bottom: 6px; margin-top: 30px; }
  h2    { font-size: 14pt; color: #2c5f2e; border-bottom: 1px solid #c8e6c9; padding-bottom: 3px; margin-top: 24px; }
  h3    { font-size: 11.5pt; color: #388e3c; margin-top: 16px; }
  table { width: 100%; border-collapse: collapse; margin: 8px 0 16px 0; font-size: 10pt; }
  th    { background: #2c5f2e; color: white; padding: 6px 9px; text-align: left; }
  td    { padding: 5px 9px; border-bottom: 1px solid #e0e0e0; vertical-align: top; }
  tr:nth-child(even) td { background: #f9fbe7; }
  code  { background: #f0f0f0; padding: 1px 4px; border-radius: 2px; font-size: 9.5pt; }
  .ok      { color: #2c5f2e; }
  .partial { color: #e65100; }
  .todo    { color: #757575; }
  .note    { background: #f5f5f5; border-left: 4px solid #2c5f2e; padding: 6px 12px; font-size: 10pt; color: #444; font-style: italic; }
  .cover   { text-align: center; padding: 60px 0 40px 0; }
  .cover h1 { font-size: 28pt; border: none; }
  .page-break { page-break-before: always; }
  li   { margin: 3px 0; }
  li.done { color: #aaa; text-decoration: line-through; }
  li.todo { color: #555; }
  p    { margin: 4px 0; }
  .footer { text-align: center; color: #aaa; font-size: 9pt; margin-top: 40px; }
</style>
</head>
<body>

<div class="cover">
  <h1>PetsMatch</h1>
  <p style="font-size:15pt; color:#388e3c; margin:6px 0 0 0;">Cahier des charges &amp; Suivi de tâches</p>
  <p style="color:#888; font-size:10pt; margin:8px 0 20px 0;">Mis à jour le $today</p>
  <p style="color:#555; max-width:480px; margin:0 auto; font-size:10pt;">
    Document de travail à usage interne — décrit l'ensemble des fonctionnalités,
    leur état d'avancement et le planning de développement.
  </p>
</div>

<div class="page-break"></div>
<h1>Cahier des charges fonctionnel</h1>
$cdcHtml

<div class="page-break"></div>
<h1>Suivi des tâches</h1>
$tasksHtml

<p class="footer">PetsMatch © 2026 — document généré automatiquement le $today</p>
</body>
</html>
"@

# ── Écriture HTML ─────────────────────────────────────────────────────────────
# UTF-8 sans BOM (Out-File utf8 ajoute un BOM que Word interprète mal)
[System.IO.File]::WriteAllText($htmlPath, $html, (New-Object System.Text.UTF8Encoding $false))
Write-Host "HTML genere."

# ── Conversion Word → DOCX + PDF ─────────────────────────────────────────────
try {
    $word = New-Object -ComObject Word.Application
    $word.Visible = $false

    $doc = $word.Documents.Open($htmlPath)
    $doc.SaveAs([ref]$docxPath, [ref]16)
    $doc.SaveAs([ref]$pdfPath,  [ref]17)
    $doc.Close($false)

    if ($OpenAfter) {
        $word.Documents.Open($docxPath) | Out-Null
        $word.Visible = $true
    } else {
        $word.Quit()
    }

    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($word) | Out-Null
    Write-Host ""
    Write-Host "✅ Export terminé !" -ForegroundColor Green
    Write-Host "   DOCX : $docxPath"
    Write-Host "   PDF  : $pdfPath"
} catch {
    Write-Host "❌ Erreur Word : $_" -ForegroundColor Red
    Write-Host "   Le fichier HTML est disponible : $htmlPath"
}
