<#
  Genera una lista IPTV dei canali italiani in chiaro (FTA) con EPG.

  Sorgenti:
    - Free-TV/IPTV  (solo canali free-to-air, flussi ufficiali)  https://github.com/Free-TV/IPTV
    - iptv-org/iptv (canali italiani pubblici, integrazione)     https://github.com/iptv-org/iptv
    - EPG epgshare01 Italia                                      https://epgshare01.online

  Uso:  powershell -ExecutionPolicy Bypass -File genera_lista.ps1 [-Uscita lista_italia.m3u] [-NoCheck] [-Backup]
    -NoCheck  salta la verifica dei flussi (più veloce, ma include link morti)
    -Backup   tiene anche i flussi alternativi funzionanti dello stesso canale
#>
param(
  [string]$Uscita = (Join-Path $PSScriptRoot 'lista_italia.m3u'),
  [switch]$NoCheck,
  [switch]$Backup,
  [int]$Timeout = 10,
  [int]$Paralleli = 24
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$FONTE_FREETV = 'https://raw.githubusercontent.com/Free-TV/IPTV/master/playlists/playlist_italy.m3u8'
$FONTE_IPTVORG = 'https://iptv-org.github.io/iptv/countries/it.m3u'
$EPG_URL = 'https://epgshare01.online/epgshare01/epg_ripper_IT1.xml.gz'
$UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36'

function Scarica([string]$url) {
  $wc = New-Object Net.WebClient
  $wc.Headers['User-Agent'] = $UA
  $wc.DownloadData($url)
}

function Normalizza([string]$s) {
  $s = $s.ToLowerInvariant()
  $s = [regex]::Replace($s, '\(.*?\)|\[.*?\]', '')          # (1080p) [Not 24/7]
  $s = [regex]::Replace($s, '[Ⓐ-ⓩ]', '')          # marcatori Free-TV (geo, youtube...)
  $s = [regex]::Replace($s, '\.(it|va|sm|ch|fr|de)(@.*)?$', '')
  $s = [regex]::Replace($s, '\b(hd|fhd|uhd|sd|tv|channel)\b', ' ')
  [regex]::Replace($s, '[^a-z0-9]', '')
}

function Leggi-M3U([byte[]]$dati, [string]$fonte) {
  $righe = [Text.Encoding]::UTF8.GetString($dati) -split "`r?`n"
  $voci = @(); $cur = $null
  foreach ($r in $righe) {
    $r = $r.Trim()
    if ($r -like '#EXTINF*') {
      $attr = @{}
      foreach ($m in [regex]::Matches($r, '([\w-]+)="([^"]*)"')) { $attr[$m.Groups[1].Value] = $m.Groups[2].Value }
      $nome = ($r -replace '^.*?,(?=[^"]*$)', '').Trim()
      $cur = [pscustomobject]@{ Nome = $nome; Attr = $attr; Opz = @(); Url = $null; Fonte = $fonte; UA = $null; Referer = $null }
    }
    elseif ($cur -and $r -like '#EXTVLCOPT*') {
      $cur.Opz += $r
      if ($r -match 'http-user-agent=(.+)$') { $cur.UA = $matches[1] }
      if ($r -match 'http-referrer=(.+)$') { $cur.Referer = $matches[1] }
    }
    elseif ($cur -and $r -and -not $r.StartsWith('#')) {
      $cur.Url = $r; $voci += $cur; $cur = $null
    }
  }
  $voci
}

function Categoria($v, [bool]$haEpg) {
  $n = Normalizza $v.Nome
  switch -regex ($n) {
    '^(camera|senato)'                                   { return 'Istituzionali' }
    '^rai'                                               { return 'Rai' }
    '^(rete4|canale5|italia1|italia2$|20(mediaset)?$|iris|la5|cine34|focus|topcrime|twentyseven|27twentyseven|mediasetextra|tgcom24|boing|cartoonito|mediaset)' { return 'Mediaset' }
    '(kids|frisbee|kdolce|kdue|gulp|yoyo|deakids|superkids|cartoon|manga)' { return 'Bambini' }
    '(news|tg24|tgnorba|^tg|euronews|radio24)'           { return 'Notizie' }
    '(sport|tennis|solocalcio|seriea|motor)'             { return 'Sport' }
    '(radio|music|mtv|deejay|kisskiss|m2o|rds|rtl|virgin|105|vh1)' { return 'Musica e Radiovisione' }
  }
  $chno = 0; [void][int]::TryParse([string]$v.Attr['tvg-chno'], [ref]$chno)
  if (($chno -ge 1 -and $chno -le 99) -or $haEpg) { 'Nazionali' } else { 'Locali e altri' }
}

Write-Host '1/4  Scarico le playlist sorgente...'
$voci = @()
$voci += Leggi-M3U (Scarica $FONTE_FREETV) 'Free-TV'
$org = Leggi-M3U (Scarica $FONTE_IPTVORG) 'iptv-org'
# da iptv-org teniamo solo canali italiani (scarta canali FAST esteri doppiati: Pluto, Samsung, ecc.)
$org = $org | Where-Object { $_.Attr['tvg-id'] -match '\.(it|va|sm)(@|$)' -and $_.Url -notmatch 'pluto\.tv|samsung|wurl|amagi|rakuten' }
$voci += $org
# i link YouTube non sono riproducibili nei player IPTV senza resolver
$voci = $voci | Where-Object { $_.Url -notmatch 'youtube\.com|youtu\.be' }
Write-Host "     $($voci.Count) flussi candidati"

Write-Host '2/4  Scarico e indicizzo la guida EPG...'
$gz = New-Object IO.Compression.GZipStream((New-Object IO.MemoryStream(, (Scarica $EPG_URL))), [IO.Compression.CompressionMode]::Decompress)
$xml = [xml](New-Object IO.StreamReader($gz, [Text.Encoding]::UTF8)).ReadToEnd()
$epgIds = @{}; $epgNomi = @{}
foreach ($c in $xml.tv.channel) {
  $epgIds[$c.id] = $true
  $k = Normalizza $c.id; if ($k -and -not $epgNomi.ContainsKey($k)) { $epgNomi[$k] = $c.id }
  foreach ($dn in @($c.'display-name')) {
    $t = if ($dn -is [string]) { $dn } else { $dn.'#text' }
    $k = Normalizza $t; if ($k -and -not $epgNomi.ContainsKey($k)) { $epgNomi[$k] = $c.id }
  }
}
foreach ($v in $voci) {
  $id = $v.Attr['tvg-id']
  if ($id -and $epgIds.ContainsKey($id)) { $v | Add-Member EpgId $id; continue }
  $trovato = $null
  foreach ($k in @((Normalizza $v.Nome), (Normalizza $id), (Normalizza $v.Attr['tvg-name']))) {
    if ($k -and $epgNomi.ContainsKey($k)) { $trovato = $epgNomi[$k]; break }
  }
  if (-not $trovato) {
    # corrispondenza approssimata: "tgcom24" -> "tgcom", "twentyseven" -> "27twentyseven"
    $n = Normalizza $v.Nome
    if ($n.Length -ge 5) {
      $trovato = $epgNomi.Keys | Where-Object { $_.Length -ge 5 -and (($n -match ('^' + [regex]::Escape($_) + '\d+$')) -or $_.EndsWith($n)) } |
        Sort-Object Length -Descending | Select-Object -First 1 | ForEach-Object { $epgNomi[$_] }
    }
  }
  $v | Add-Member EpgId $trovato
}

if (-not $NoCheck) {
  Write-Host "3/4  Verifico i flussi ($Paralleli in parallelo, timeout ${Timeout}s)..."
  $verifica = {
    param($url, $ua, $ref, $timeout)
    try {
      [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
      $req = [Net.HttpWebRequest]::Create($url)
      $req.UserAgent = $ua; if ($ref) { $req.Referer = $ref }
      $req.Timeout = $timeout * 1000; $req.ReadWriteTimeout = $timeout * 1000
      $req.AllowAutoRedirect = $true
      $res = $req.GetResponse()
      $buf = New-Object byte[] 2048
      $n = $res.GetResponseStream().Read($buf, 0, 2048)
      $ct = $res.ContentType; $res.Close()
      $txt = [Text.Encoding]::ASCII.GetString($buf, 0, [Math]::Max($n, 0))
      ($txt -match '#EXTM3U') -or ($ct -match 'video|mpegurl|octet-stream|dash') -or ($n -gt 0 -and $buf[0] -eq 0x47)
    } catch { $false }
  }
  $pool = [RunspaceFactory]::CreateRunspacePool(1, $Paralleli); $pool.Open()
  $jobs = foreach ($v in $voci) {
    $ps = [PowerShell]::Create().AddScript($verifica).AddArgument($v.Url).AddArgument($(if ($v.UA) { $v.UA } else { $UA })).AddArgument($v.Referer).AddArgument($Timeout)
    $ps.RunspacePool = $pool
    [pscustomobject]@{ V = $v; PS = $ps; H = $ps.BeginInvoke() }
  }
  $i = 0
  foreach ($j in $jobs) {
    $ok = $false; try { $ok = [bool]($j.PS.EndInvoke($j.H) | Select-Object -Last 1) } catch {}
    $j.V | Add-Member Ok $ok; $j.PS.Dispose(); $i++
    if ($i % 50 -eq 0) { Write-Host "     $i/$($jobs.Count)" }
  }
  $pool.Close()
  $voci = $voci | Where-Object { $_.Ok }
  Write-Host "     $($voci.Count) flussi funzionanti"
} else { Write-Host '3/4  Verifica flussi saltata (-NoCheck)' }

Write-Host '4/4  Deduplico e scrivo la playlist...'
$canali = [ordered]@{}; $perNome = @{}; $urlVisti = @{}
foreach ($v in $voci) {   # Free-TV viene prima: a parità di canale vince il flusso ufficiale
  if ($urlVisti.ContainsKey($v.Url)) { continue }   # stesso flusso già usato da un altro canale
  $urlVisti[$v.Url] = $true
  $nk = Normalizza $v.Nome
  $k = if ($v.EpgId) { "epg:$($v.EpgId)" } elseif ($perNome.ContainsKey($nk)) { $perNome[$nk] } else { "n:$nk" }
  if (-not $perNome.ContainsKey($nk)) { $perNome[$nk] = $k }
  if (-not $canali.Contains($k)) { $canali[$k] = New-Object Collections.ArrayList }
  if (-not ($canali[$k] | Where-Object { $_.Url -eq $v.Url })) { [void]$canali[$k].Add($v) }
}
$ordineCat = 'Rai', 'Mediaset', 'Nazionali', 'Notizie', 'Sport', 'Bambini', 'Musica e Radiovisione', 'Istituzionali', 'Locali e altri'
$righe = New-Object Collections.Generic.List[string]
$righe.Add("#EXTM3U x-tvg-url=`"$EPG_URL`" url-tvg=`"$EPG_URL`"")
$elenco = foreach ($k in $canali.Keys) {
  $lista = $canali[$k]; $p = $lista[0]
  $nome = ([regex]::Replace($p.Nome, '\s*(\(.*?\)|\[.*?\]|[Ⓐ-ⓩ])', '')).Trim()
  $chno = 999; [void][int]::TryParse([string]$p.Attr['tvg-chno'], [ref]$chno); if ($chno -eq 0) { $chno = 999 }
  $logo = ($lista | ForEach-Object { $_.Attr['tvg-logo'] } | Where-Object { $_ } | Select-Object -First 1)
  [pscustomobject]@{ Nome = $nome; Chno = $chno; Logo = $logo; Epg = $p.EpgId; Cat = (Categoria $p ([bool]$p.EpgId)); Flussi = $(if ($Backup) { $lista } else { @($p) }) }
}
$elenco = $elenco | Sort-Object @{ e = { [array]::IndexOf($ordineCat, $_.Cat) } }, Chno, Nome
foreach ($c in $elenco) {
  $n = 0
  foreach ($f in $c.Flussi) {
    $titolo = if ($n -eq 0) { $c.Nome } else { "$($c.Nome) (backup $n)" }
    $a = "tvg-id=`"$($c.Epg)`" tvg-name=`"$($c.Nome)`""
    if ($c.Chno -lt 999) { $a += " tvg-chno=`"$($c.Chno)`"" }
    if ($c.Logo) { $a += " tvg-logo=`"$($c.Logo)`"" }
    $righe.Add("#EXTINF:-1 $a group-title=`"$($c.Cat)`",$titolo")
    foreach ($o in $f.Opz) { $righe.Add($o) }
    $righe.Add($f.Url); $n++
  }
}
[IO.File]::WriteAllLines($Uscita, $righe, (New-Object Text.UTF8Encoding($false)))

$conEpg = @($elenco | Where-Object { $_.Epg }).Count
Write-Host ''
Write-Host "Fatto: $($elenco.Count) canali, $conEpg con EPG -> $Uscita"
$elenco | Group-Object Cat | Sort-Object { [array]::IndexOf($ordineCat, $_.Name) } | ForEach-Object { Write-Host ("  {0,-24} {1,3}" -f $_.Name, $_.Count) }
