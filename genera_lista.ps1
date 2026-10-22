<#
  Genera una lista IPTV dei canali italiani in chiaro (FTA) con EPG.

  Sorgenti:
    - Free-TV/IPTV  (solo canali free-to-air, flussi ufficiali)  https://github.com/Free-TV/IPTV
    - iptv-org/iptv (canali italiani pubblici, integrazione)     https://github.com/iptv-org/iptv
    - EPG epgshare01 Italia                                      https://epgshare01.online

  Uso:  powershell -ExecutionPolicy Bypass -File genera_lista.ps1 [-Uscita lista_italia.m3u] [-NoCheck] [-Backup] [-TieniGeo]
    -NoCheck   salta la verifica dei flussi (più veloce, ma include link morti)
    -Backup    tiene anche i flussi alternativi funzionanti dello stesso canale
    -TieniGeo  non verifica i flussi geobloccati (visibili solo dall'Italia) e li tiene comunque:
               da usare quando lo script gira fuori dall'Italia (es. GitHub Actions)
    -MinCanali se la lista risultante ha meno canali di così, non la scrive (sorgenti irraggiungibili)
#>
param(
  [string]$Uscita = (Join-Path $PSScriptRoot 'lista_italia.m3u'),
  [switch]$NoCheck,
  [switch]$Backup,
  [switch]$TieniGeo,
  [int]$MinCanali = 150,
  [int]$Timeout = 10,
  [int]$Paralleli = 24
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$FONTE_FREETV = 'https://raw.githubusercontent.com/Free-TV/IPTV/master/playlists/playlist_italy.m3u8'
$FONTE_IPTVORG = 'https://iptv-org.github.io/iptv/countries/it.m3u'
$EPG_URL = 'https://epgshare01.online/epgshare01/epg_ripper_IT1.xml.gz'
$UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36'

# Numerazione LCN nazionale del digitale terrestre (fonte: Wikipedia, "Servizi televisivi digitali
# terrestri nazionali in Italia", ottobre 2026). Ogni numero ha uno o più nomi con cui il canale
# compare nelle sorgenti. I canali locali (LCN 10-19, 71-99, 600+) cambiano per regione: restano senza numero.
$LCN = @{
  1 = 'Rai 1'; 2 = 'Rai 2'; 3 = 'Rai 3'; 4 = 'Rete 4'; 5 = 'Canale 5'; 6 = 'Italia 1'; 7 = 'La7'; 8 = 'TV8'; 9 = 'Nove'
  20 = '20 Mediaset', '20'; 21 = 'Rai 4'; 22 = 'Iris'; 23 = 'Rai 5'; 24 = 'Rai Movie'; 25 = 'Rai Premium'; 26 = 'Cielo'
  27 = '27 Twentyseven', 'Twentyseven'; 28 = 'TV2000', 'TV 2000'; 29 = 'La7 Cinema', 'La7d'; 30 = 'La 5'; 31 = 'Real Time'
  32 = 'QVC'; 33 = 'Food Network'; 34 = 'Cine34'; 35 = 'Focus'; 36 = 'RTL 102.5'; 37 = 'Discovery Channel', 'Discovery'
  38 = 'Giallo'; 39 = 'Top Crime'; 40 = 'Boing'; 41 = 'K2'; 42 = 'Rai Gulp'; 43 = 'Rai YoYo'; 44 = 'Frisbee'
  45 = 'Boing Plus'; 46 = 'Cartoonito'; 47 = 'Super!'; 48 = 'Rai News 24'; 49 = 'Italia 2', 'Mediaset Italia2'
  50 = 'Sky TG24'; 51 = 'TGCOM 24', 'TGCom24'; 52 = 'DMAX'; 54 = 'Rai Storia'; 55 = 'Mediaset Extra'
  56 = 'HGTV', 'HGTV – Home & Garden Tv'; 58 = 'Rai Sport'; 59 = 'Turbo', 'Discovery Turbo', 'Motor Trend'
  60 = 'Sportitalia', 'Sportitalia Plus'; 61 = 'Club TV'; 62 = 'Donna Sport TV'; 63 = 'IlSole24ORE TV'; 64 = 'SuperTennis'
  65 = 'Alma TV'; 66 = 'Radio 105 TV', 'Radio 105'; 67 = 'R101 TV'; 68 = 'BOM Channel'; 69 = 'Deejay TV'
  70 = 'Radio Italia TV', 'RadioItaliaTV'; 101 = 'Rai 4K'; 145 = 'Padre Pio TV'; 151 = 'EQUtv'; 157 = 'Fascino TV'
  158 = 'Radio Kiss Kiss TV'; 167 = 'VH1'; 202 = 'Rai Radio 2 Visual Radio', 'Rai Radio 2 Visual'; 232 = 'Match Music'
  233 = 'RTL 102.5 Caliente'; 234 = 'Cusano News 7'; 236 = 'Man-ga'; 241 = 'France 24'
  246 = 'Radio 24 TV', 'Radio24-IlSole24OreTV'; 247 = 'BeJoy Kids'; 253 = 'Radio Radio TV'; 255 = 'Maria Vision'
  257 = 'Gambero Rosso'; 258 = 'RadioFreccia'; 265 = 'RDS Social TV'; 266 = 'Radio Zeta'; 550 = 'San Marino RTV', 'RTV San Marino'
  739 = 'RTL 102.5 Traffic'; 740 = 'RTL 102.5 Best'; 741 = 'RTL 102.5 Napule'; 742 = 'RTL 102.5 Disco'
  744 = 'RTL 102.5 Bro&Sis'; 828 = 'Class CNBC'; 833 = 'SuperSix'
}

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
      # Free-TV segna con il simbolo (G) cerchiato i flussi visibili solo dall'Italia
      $cur = [pscustomobject]@{ Nome = $nome; Attr = $attr; Opz = @(); Url = $null; Fonte = $fonte; UA = $null; Referer = $null; Geo = ($nome -match 'Ⓖ') }
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

$lcnPerNome = @{}
foreach ($num in $LCN.Keys) { foreach ($alias in @($LCN[$num])) { $lcnPerNome[(Normalizza $alias)] = $num } }

function Trova-LCN($v) {
  foreach ($k in @((Normalizza $v.Nome), (Normalizza $v.Attr['tvg-name']))) {
    if ($k -and $lcnPerNome.ContainsKey($k)) { return $lcnPerNome[$k] }
  }
  9999
}

function Categoria($v, [bool]$haEpg, [int]$lcn) {
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
  if ($lcn -lt 9999 -or $haEpg) { 'Nazionali' } else { 'Locali e altri' }
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
# A parità di canale vince il flusso dell'emittente rispetto alle ritrasmissioni di terzi (più stabile).
# Il relinker Rai rifiuta lo user-agent di VLC: gli si dichiara quello di un browser.
$i = 0
foreach ($v in $voci) {
  $v | Add-Member Indice ($i++)
  $v | Add-Member Ufficiale ($v.Url -match '^https?://([\w-]+\.)*(rai\.it|mediaset\.net|la7\.it)/')
  if ($v.Url -match 'mediapolis\.rai\.it/relinker' -and -not $v.UA) { $v.UA = $UA; $v.Opz += "#EXTVLCOPT:http-user-agent=$UA" }
}
$voci = $voci | Sort-Object @{ e = { -not $_.Ufficiale } }, Indice
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
    if ($TieniGeo -and $v.Geo) { $v | Add-Member Ok $true; continue }
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
  $chno = Trova-LCN $p
  $logo = ($lista | ForEach-Object { $_.Attr['tvg-logo'] } | Where-Object { $_ } | Select-Object -First 1)
  [pscustomobject]@{ Nome = $nome; Chno = $chno; Logo = $logo; Epg = $p.EpgId; Cat = (Categoria $p ([bool]$p.EpgId) $chno); Flussi = $(if ($Backup) { $lista } else { @($p) }) }
}
# prima i canali con LCN nell'ordine del telecomando, poi gli altri per gruppo
$elenco = $elenco | Sort-Object Chno, @{ e = { [array]::IndexOf($ordineCat, $_.Cat) } }, Nome
if ($elenco.Count -lt $MinCanali) {
  throw "Solo $($elenco.Count) canali (minimo $MinCanali): le sorgenti sembrano irraggiungibili, la lista non viene sovrascritta."
}
foreach ($c in $elenco) {
  $n = 0
  foreach ($f in $c.Flussi) {
    $titolo = if ($n -eq 0) { $c.Nome } else { "$($c.Nome) (backup $n)" }
    $a = "tvg-id=`"$($c.Epg)`" tvg-name=`"$titolo`""
    if ($c.Chno -lt 9999 -and $n -eq 0) { $a += " tvg-chno=`"$($c.Chno)`"" }
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
