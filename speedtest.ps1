$wc = New-Object System.Net.WebClient
$url = "http://speedtest.ftp.otenet.gr/files/test1Mb.db"
$sw = [System.Diagnostics.Stopwatch]::StartNew()
try {
    $data = $wc.DownloadData($url)
    $sw.Stop()
    $mb = $data.Length / 1MB
    $sec = $sw.Elapsed.TotalSeconds
    $mbps = [math]::Round($mb * 8 / $sec, 2)
    Write-Host "File size: $([math]::Round($mb,2)) MB"
    Write-Host "Time: $([math]::Round($sec,2)) sec"
    Write-Host "Speed: $mbps Mbps"
} catch {
    Write-Host "Error: $_"
}
