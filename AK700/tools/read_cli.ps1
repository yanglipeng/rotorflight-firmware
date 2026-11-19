$ErrorActionPreference = "Stop"
$portName = "COM4"
$outFile  = "C:\project\rotorflight-firmware\obj\live_cli_raw.txt"

$p = New-Object System.IO.Ports.SerialPort($portName, 115200, [System.IO.Ports.Parity]::None, 8, [System.IO.Ports.StopBits]::One)
$p.ReadTimeout = 500
$p.WriteTimeout = 500
$p.DtrEnable = $true
$p.Open()
Start-Sleep -Milliseconds 300
$p.DiscardInBuffer()

function Read-Until([string]$needle, [int]$timeoutMs) {
    $sb = New-Object System.Text.StringBuilder
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.ElapsedMilliseconds -lt $timeoutMs) {
        try {
            $chunk = $p.ReadExisting()
            if ($chunk.Length -gt 0) { [void]$sb.Append($chunk) }
        } catch { }
        if ($sb.ToString() -match $needle) { break }
        Start-Sleep -Milliseconds 80
    }
    return $sb.ToString()
}

$all = New-Object System.Text.StringBuilder

$p.Write("#")
$all.Append((Read-Until "cli" 4000)) | Out-Null
Start-Sleep -Milliseconds 400

$p.Write("version`r`n")
$all.Append((Read-Until "# " 3000)) | Out-Null

$p.Write("diff all`r`n")
$all.Append((Read-Until "# " 25000)) | Out-Null

$p.Write("exit`r`n")
$all.Append((Read-Until " " 1500)) | Out-Null

$p.Close()
[System.IO.File]::WriteAllText($outFile, $all.ToString(), [System.Text.Encoding]::UTF8)
Write-Output ("captured bytes: " + $all.Length)
