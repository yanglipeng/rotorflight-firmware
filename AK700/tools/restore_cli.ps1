# Restore AK700_cli_restore_4.7.0.txt into the flight controller CLI.
# Skips comment lines (non-ASCII) and blank lines.
# IMPORTANT: read the RX buffer after every command, otherwise the USB VCP
# RX buffer fills up and the next Write blocks until timeout.

$ErrorActionPreference = 'Continue'

$port    = 'COM4'
$baud    = 115200
$file    = 'C:\project\rotorflight-firmware\AK700\config\AK700_cli_restore_4.7.0.txt'
$logFile = 'C:\project\rotorflight-firmware\obj\restore_log.txt'

$CR = [string][char]13
$LF = [string][char]10

$lines = @(Get-Content -Path $file -Encoding UTF8 |
    Where-Object { $_ -notmatch '^\s*#' -and $_ -notmatch '^\s*$' })

Write-Host "Commands to send: $($lines.Count)"

$sp = New-Object System.IO.Ports.SerialPort $port, $baud, 'None', 8, 'One'
$sp.ReadTimeout = 300
$sp.WriteTimeout = 2000

$log = New-Object System.Text.StringBuilder

try {
    $sp.Open()
    Start-Sleep -Milliseconds 300
    try { $sp.DiscardInBuffer() } catch { }
    try { $sp.Write("#$CR$LF") } catch { }
    Start-Sleep -Milliseconds 900
    try { [void]$log.Append($sp.ReadExisting()) } catch { }

    $sent = 0
    foreach ($l in $lines) {
        try { $sp.Write("$l$CR$LF") } catch { [void]$log.Append("$LF<<write fail: $l>>$LF") }
        Start-Sleep -Milliseconds 60
        try { [void]$log.Append($sp.ReadExisting()) } catch { }
        $sent++
    }
    Write-Host "Sent: $sent"
    Start-Sleep -Milliseconds 4000
    try { while ($sp.BytesToRead -gt 0) { [void]$log.Append($sp.ReadExisting()); Start-Sleep -Milliseconds 80 } } catch { }

} catch {
    Write-Host "Serial error: $($_.Exception.Message)"
} finally {
    Start-Sleep -Milliseconds 150
    try { if ($sp.IsOpen) { $sp.Close() } } catch { }
}

$out = $log.ToString()
$out = $out.Replace($CR, '')
$out = $out.Replace([string][char]0, '')
$out | Out-File -FilePath $logFile -Encoding utf8
Write-Host "Log: $logFile  chars=$($out.Length)"

$errs = @(($out -split "`n") | Where-Object { $_ -match 'ERROR|Invalid|Unknown|unknown command|write fail' })
if ($errs.Count -gt 0) {
    Write-Host "=== $($errs.Count) suspicious lines ==="
    $errs | Select-Object -First 30 | ForEach-Object { Write-Host "  $_" }
} else {
    Write-Host "=== clean: no ERROR / Invalid / Unknown ==="
}
