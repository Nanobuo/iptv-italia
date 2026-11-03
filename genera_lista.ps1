<#
  Genera una lista IPTV dei canali italiani in chiaro (FTA) con EPG.

  Sorgenti:
    - Free-TV/IPTV  (solo canali free-to-air, flussi ufficiali)  https://github.com/Free-TV/IPTV
    - iptv-org/iptv (canali italiani pubblici, integrazione)     https://github.com/iptv-org/iptv
    - EPG: epgshare01 (principale), open-epg.com e iptv-epg.org (integrazione)
      (open-epg italy1 e italy4 esclusi: un solo programma per canale, o quasi nessun canale con programmi)

  File generati (accanto allo script, salvo diversa indicazione):
    lista_italia.m3u     tutti i canali
    lista_nazionali.m3u  solo i canali con numero LCN nazionale
    guida.xml.gz         guida EPG dei soli canali in lista, unendo tutte le fonti
    STATO.md             rapporto sullo stato dei canali
    stato.json           ultima data in cui ogni flusso ha risposto (per la tolleranza)

  Uso:  powershell -ExecutionPolicy Bypass -File genera_lista.ps1 [-NoCheck] [-Backup] [-TieniGeo]
    -NoCheck   salta la verifica dei flussi (più veloce, ma include link morti)
    -Backup    tiene anche i flussi alternativi funzionanti dello stesso canale
    -TieniGeo  non verifica i flussi geobloccati (visibili solo dall'Italia) e li tiene comunque:
               da usare quando lo script gira fuori dall'Italia (es. GitHub Actions)
    -GiorniTolleranza  un flusso che non risponde resta in lista se ha funzionato negli ultimi N giorni
    -MinCanali se la lista risultante ha meno canali di così, non la scrive (sorgenti irraggiungibili)
#>
param(
  [string]$Uscita = (Join-Path $PSScriptRoot 'lista_italia.m3u'),
  [string]$UscitaNazionali = (Join-Path $PSScriptRoot 'lista_nazionali.m3u'),
  [string]$Guida = (Join-Path $PSScriptRoot 'guida.xml.gz'),
  [string]$Rapporto = (Join-Path $PSScriptRoot 'STATO.md'),
  [string]$Stato = (Join-Path $PSScriptRoot 'stato.json'),
  [switch]$NoCheck,
  [switch]$Backup,
  [switch]$TieniGeo,
  [int]$GiorniTolleranza = 3,
  [int]$MinCanali = 150,
  [int]$Timeout = 10,
  [int]$Paralleli = 24
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$FONTE_FREETV = 'https://raw.githubusercontent.com/Free-TV/IPTV/master/playlists/playlist_italy.m3u8'
$FONTE_IPTVORG = 'https://iptv-org.github.io/iptv/countries/it.m3u'
# La prima fonte EPG è la principale (obbligatoria); le altre coprono solo i canali che la prima non ha.
$FONTI_EPG = @(
  @{ Nome = 'epgshare01'; Url = 'https://epgshare01.online/epgshare01/epg_ripper_IT1.xml.gz' }
  @{ Nome = 'open-epg italy2'; Url = 'https://www.open-epg.com/files/italy2.xml' }
  @{ Nome = 'open-epg italy3'; Url = 'https://www.open-epg.com/files/italy3.xml' }
  @{ Nome = 'iptv-epg.org'; Url = 'https://iptv-epg.org/files/epg-it.xml.gz' }
)
# guida.xml.gz è pubblicata come file della release "dati" del repository (vedi workflow)
$GUIDA_URL = 'https://github.com/Nanobuo/iptv-italia/releases/download/dati/guida.xml.gz'
$UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36'

# Numerazione LCN nazionale del digitale terrestre (fonte: Wikipedia, "Servizi televisivi digitali
# terrestri nazionali in Italia", ottobre 2026). Ogni numero ha uno o più nomi con cui il canale
# compare nelle sorgenti. I canali locali (LCN 10-19, 71-99, 600+) cambiano per regione: restano senza numero.
# STATO.md segnala i canali con guida ma senza numero: candidati da aggiungere qui.
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
  744 = 'RTL 102.5 Bro&Sis'; 828 = 'Class CNBC'; 833 = 'SuperSix'; 441 = 'Italian Fishing TV'; 888 = 'Caccia e Pesca'
}

function Scarica([string]$url) {
  $wc = New-Object Net.WebClient
  $wc.Headers['User-Agent'] = $UA
  $b = $wc.DownloadData($url)
  if ($b.Length -gt 2 -and $b[0] -eq 0x1f -and $b[1] -eq 0x8b) {   # gzip
    $gz = New-Object IO.Compression.GZipStream((New-Object IO.MemoryStream(, $b)), [IO.Compression.CompressionMode]::Decompress)
    $ms = New-Object IO.MemoryStream; $gz.CopyTo($ms); $b = $ms.ToArray()
  }
  , $b
}

function Normalizza([string]$s) {
  $s = $s.ToLowerInvariant()
  $s = [regex]::Replace($s, '^[a-z]{2} - ', '')             # prefisso paese di alcune guide ("IT - Canale 5")
  $s = [regex]::Replace($s, '\(.*?\)|\[.*?\]', '')          # (1080p) [Not 24/7]
  $s = [regex]::Replace($s, '[Ⓐ-ⓩ]', '')          # marcatori Free-TV (geo, youtube...)
  $s = [regex]::Replace($s, '\.(it|va|sm|ch|fr|de)(@.*)?$', '')
  $s = [regex]::Replace($s, '\b(hd|fhd|uhd|sd|tv|channel)\b', ' ')
  [regex]::Replace($s, '[^a-z0-9]', '')
}

# variante che non scarta parole come "tv": distingue "TV 2000" da "2000"
function Sciolto([string]$s) {
  [regex]::Replace([regex]::Replace($s.ToLowerInvariant(), '^[a-z]{2} - ', ''), '[^a-z0-9]', '')
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

function Scrivi-M3U([string]$file, $canali) {
  $righe = New-Object Collections.Generic.List[string]
  $righe.Add("#EXTM3U x-tvg-url=`"$GUIDA_URL`" url-tvg=`"$GUIDA_URL`"")
  foreach ($c in $canali) {
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
  [IO.File]::WriteAllLines($file, $righe, (New-Object Text.UTF8Encoding($false)))
}

# Fonti scelte a mano, che hanno la precedenza su quelle delle playlist sorgente.
# Rai 2: relinker ufficiale, fissato qui per non perderlo se sparisce dalle sorgenti.
$FONTI_FISSE = @(
  @{ Nome = 'Rai 2'; Id = 'Rai2.it'; Url = 'https://mediapolis.rai.it/relinker/relinkerServlet.htm?cont=308718&output=7&forceUserAgent=raiplayappletv' }
)

# Server che rispondono solo dall'Italia ma che le sorgenti non segnalano come geobloccati.
# Con -TieniGeo (GitHub Actions) i loro flussi restano in lista senza verifica, come quelli segnalati.
# Per aggiungerne: in STATO.md cerca i canali che "non rispondono da N giorni" e prova il flusso dall'Italia.
$HOST_SOLO_ITALIA = @(
  'live-embed.supertennix.hiway.media'   # SuperTennis
  'ippicabetflag-live.morescreens.com'   # EQUtv
  'distribution.sportitalialive.it'      # Lazio Style Channel
  'nuovatv.net'                          # Nuova Tv 2
  'www.theclubfactory.com'               # Tele Club Italia
  '64b16f23efbee.streamlock.net'         # Televallo Trapani
)

Write-Host '1/5  Scarico le playlist sorgente...'
$voci = @()
foreach ($f in $FONTI_FISSE) {
  $voci += [pscustomobject]@{ Nome = $f.Nome; Attr = @{ 'tvg-id' = $f.Id; 'tvg-name' = $f.Nome }; Opz = @(); Url = $f.Url; Fonte = 'fissa'; UA = $null; Referer = $null; Geo = $true }
}
$voci += Leggi-M3U (Scarica $FONTE_FREETV) 'Free-TV'
$org = Leggi-M3U (Scarica $FONTE_IPTVORG) 'iptv-org'
# da iptv-org teniamo solo canali italiani (scarta canali FAST esteri doppiati: Pluto, Samsung, ecc.)
$org = $org | Where-Object { $_.Attr['tvg-id'] -match '\.(it|va|sm)(@|$)' -and $_.Url -notmatch 'pluto\.tv|samsung|wurl|amagi|rakuten' }
$voci += $org
# i link YouTube non sono riproducibili nei player IPTV senza resolver
$voci = $voci | Where-Object { $_.Url -notmatch 'youtube\.com|youtu\.be' }
foreach ($v in $voci) {
  $u = $null
  if ([Uri]::TryCreate($v.Url, 'Absolute', [ref]$u) -and $HOST_SOLO_ITALIA -contains $u.Host) { $v.Geo = $true }
}
# Ordine di preferenza a parità di canale:
#   0 fonti fisse; 1 flussi ufficiali delle emittenti (Rai, Mediaset, La7), più stabili; 2 ritrasmissioni di terzi.
# Il relinker Rai rifiuta lo user-agent di VLC: gli si dichiara quello di un browser.
$i = 0
foreach ($v in $voci) {
  $v | Add-Member Indice ($i++)
  $priorita = if ($v.Fonte -eq 'fissa') { 0 }
              elseif ($v.Url -match '^https?://([\w-]+\.)*(rai\.it|mediaset\.net|la7\.it)/') { 1 }
              else { 2 }
  $v | Add-Member Priorita $priorita
  $v | Add-Member Nota ''
  if ($v.Url -match 'mediapolis\.rai\.it/relinker') {
    # modalità Apple TV: offre 1080p dove Rai lo trasmette (Rai 1, 2, 3, Sport); per gli altri resta 720p
    $v.Url = if ($v.Url -match 'forceUserAgent=') { $v.Url -replace 'forceUserAgent=[^&]*', 'forceUserAgent=raiplayappletv' } else { "$($v.Url)&forceUserAgent=raiplayappletv" }
    if (-not $v.UA) { $v.UA = $UA; $v.Opz += "#EXTVLCOPT:http-user-agent=$UA" }
  }
}
$voci = $voci | Sort-Object Priorita, Indice
Write-Host "     $($voci.Count) flussi candidati"

Write-Host '2/5  Scarico e indicizzo le guide EPG...'
# si tengono i programmi da 12 ore fa in poi; un canale senza programmi futuri non conta come coperto
$limite = (Get-Date).ToUniversalTime().AddHours(-12).ToString('yyyyMMddHHmmss')
$guide = @()
for ($g = 0; $g -lt $FONTI_EPG.Count; $g++) {
  try { $xml = [xml][Text.Encoding]::UTF8.GetString((Scarica $FONTI_EPG[$g].Url)).TrimStart([char]0xFEFF) }
  catch { if ($g -eq 0) { throw }; Write-Host "     $($FONTI_EPG[$g].Nome): non disponibile, salto"; continue }
  $conProg = @{}
  foreach ($p in $xml.tv.programme) { if (-not $p.stop -or $p.stop.Substring(0, 14) -ge $limite) { $conProg[$p.channel] = $true } }
  $ids = @{}; $nomi = @{}
  foreach ($c in $xml.tv.channel) {
    if (-not $conProg.ContainsKey($c.id)) { continue }   # canali senza programmi: inutili
    $ids[$c.id] = $true
    $chiavi = @((Normalizza $c.id))
    foreach ($dn in @($c.'display-name')) { $t = if ($dn -is [string]) { $dn } else { $dn.'#text' }; $chiavi += (Normalizza $t); $chiavi += (Sciolto $t) }
    foreach ($k in $chiavi) { if ($k -and -not $nomi.ContainsKey($k)) { $nomi[$k] = $c.id } }
  }
  $guide += [pscustomobject]@{ Indice = $g; Nome = $FONTI_EPG[$g].Nome; Xml = $xml; Ids = $ids; Nomi = $nomi }
  Write-Host "     $($FONTI_EPG[$g].Nome): $($ids.Count) canali"
}
foreach ($v in $voci) {
  $id = $v.Attr['tvg-id']; $trovato = $null; $fonte = $null
  $principale = $guide[0]
  if ($id -and $principale.Ids.ContainsKey($id)) { $trovato = $id; $fonte = $principale }
  if (-not $trovato) {
    foreach ($k in @((Normalizza $v.Nome), (Normalizza $id), (Normalizza $v.Attr['tvg-name']))) {
      if ($k -and $principale.Nomi.ContainsKey($k)) { $trovato = $principale.Nomi[$k]; $fonte = $principale; break }
    }
  }
  if (-not $trovato) {
    # corrispondenza approssimata nella guida principale: "tgcom24" -> "tgcom", "twentyseven" -> "27twentyseven"
    $n = Normalizza $v.Nome
    if ($n.Length -ge 5) {
      $trovato = $principale.Nomi.Keys | Where-Object { $_.Length -ge 5 -and (($n -match ('^' + [regex]::Escape($_) + '\d+$')) -or $_.EndsWith($n)) } |
        Sort-Object Length -Descending | Select-Object -First 1 | ForEach-Object { $principale.Nomi[$_] }
      if ($trovato) { $fonte = $principale }
    }
  }
  if (-not $trovato) {
    # guide di integrazione, solo corrispondenza esatta del nome
    foreach ($gu in ($guide | Select-Object -Skip 1)) {
      foreach ($k in @((Normalizza $v.Nome), (Sciolto $v.Nome), (Normalizza $v.Attr['tvg-name']))) {
        if ($k -and $gu.Nomi.ContainsKey($k)) { $trovato = $gu.Nomi[$k]; $fonte = $gu; break }
      }
      if ($trovato) { break }
    }
  }
  $v | Add-Member EpgId $trovato
  $v | Add-Member EpgGuida $(if ($fonte) { $fonte.Indice } else { -1 })
}

# stato.json: per ogni URL, l'ultima data in cui il flusso ha risposto
$oggi = (Get-Date).Date
$statoUrl = @{}
if (Test-Path $Stato) {
  $j = Get-Content $Stato -Raw -Encoding UTF8 | ConvertFrom-Json
  foreach ($p in $j.PSObject.Properties) { $statoUrl[$p.Name] = [datetime]::ParseExact($p.Value, 'yyyy-MM-dd', $null) }
}

if (-not $NoCheck) {
  Write-Host "3/5  Verifico i flussi ($Paralleli in parallelo, timeout ${Timeout}s)..."
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
    if ($TieniGeo -and $v.Geo) { $v | Add-Member Ok $true; $v.Nota = 'geobloccato, non verificato'; continue }
    $ps = [PowerShell]::Create().AddScript($verifica).AddArgument($v.Url).AddArgument($(if ($v.UA) { $v.UA } else { $UA })).AddArgument($v.Referer).AddArgument($Timeout)
    $ps.RunspacePool = $pool
    [pscustomobject]@{ V = $v; PS = $ps; H = $ps.BeginInvoke() }
  }
  $i = 0; $tollerati = 0
  foreach ($j in $jobs) {
    $ok = $false; try { $ok = [bool]($j.PS.EndInvoke($j.H) | Select-Object -Last 1) } catch {}
    $u = $j.V.Url
    if ($ok) { $statoUrl[$u] = $oggi }
    elseif ($statoUrl.ContainsKey($u) -and ($oggi - $statoUrl[$u]).Days -le $GiorniTolleranza) {
      # ha funzionato di recente: probabilmente un guasto temporaneo, resta in lista
      $giorni = ($oggi - $statoUrl[$u]).Days
      $ok = $true; $tollerati++
      $j.V.Nota = if ($giorni -le 1) { 'non ha risposto oggi' } else { "non risponde da $giorni giorni" }
    }
    $j.V | Add-Member Ok $ok; $j.PS.Dispose(); $i++
    if ($i % 50 -eq 0) { Write-Host "     $i/$($jobs.Count)" }
  }
  $pool.Close()
  $voci = $voci | Where-Object { $_.Ok }
  Write-Host "     $($voci.Count) flussi tenuti, di cui $tollerati per tolleranza"
  # dimentica gli URL che non rispondono da più di 30 giorni
  $salva = [ordered]@{}
  foreach ($u in ($statoUrl.Keys | Sort-Object)) { if (($oggi - $statoUrl[$u]).Days -le 30) { $salva[$u] = $statoUrl[$u].ToString('yyyy-MM-dd') } }
  [IO.File]::WriteAllText($Stato, ($salva | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
} else { Write-Host '3/5  Verifica flussi saltata (-NoCheck)' }

Write-Host '4/5  Deduplico i canali e compongo la guida...'
$canali = [ordered]@{}; $perNome = @{}; $urlVisti = @{}
foreach ($v in $voci) {   # già ordinati per preferenza: a parità di canale vince il primo
  if ($urlVisti.ContainsKey($v.Url)) { continue }   # stesso flusso già usato da un altro canale
  $urlVisti[$v.Url] = $true
  $nk = Normalizza $v.Nome
  $k = if ($v.EpgId) { "epg:$($v.EpgGuida):$($v.EpgId)" } elseif ($perNome.ContainsKey($nk)) { $perNome[$nk] } else { "n:$nk" }
  if (-not $perNome.ContainsKey($nk)) { $perNome[$nk] = $k }
  if (-not $canali.Contains($k)) { $canali[$k] = New-Object Collections.ArrayList }
  if (-not ($canali[$k] | Where-Object { $_.Url -eq $v.Url })) { [void]$canali[$k].Add($v) }
}
$ordineCat = 'Rai', 'Mediaset', 'Nazionali', 'Notizie', 'Sport', 'Bambini', 'Musica e Radiovisione', 'Istituzionali', 'Locali e altri'
$elenco = foreach ($k in $canali.Keys) {
  $lista = $canali[$k]; $p = $lista[0]
  $nome = ([regex]::Replace($p.Nome, '\s*(\(.*?\)|\[.*?\]|[Ⓐ-ⓩ])', '')).Trim()
  $chno = Trova-LCN $p
  $logo = ($lista | ForEach-Object { $_.Attr['tvg-logo'] } | Where-Object { $_ } | Select-Object -First 1)
  [pscustomobject]@{ Nome = $nome; Chno = $chno; Logo = $logo; Epg = $null; EpgId = $p.EpgId; EpgGuida = $p.EpgGuida; Cat = (Categoria $p ([bool]$p.EpgId) $chno)
                     Flussi = $(if ($Backup) { $lista } else { @($p) }); Url = $p.Url; Nota = $p.Nota }
}
# prima i canali con LCN nell'ordine del telecomando, poi gli altri per gruppo
$elenco = $elenco | Sort-Object Chno, @{ e = { [array]::IndexOf($ordineCat, $_.Cat) } }, Nome
if ($elenco.Count -lt $MinCanali) {
  throw "Solo $($elenco.Count) canali (minimo $MinCanali): le sorgenti sembrano irraggiungibili, la lista non viene sovrascritta."
}

# id della guida unita: quello della fonte principale; per le altre, lo stesso id se non è già usato
$usati = [ordered]@{}; $perGuida = @{}
foreach ($c in ($elenco | Where-Object { $_.EpgId } | Sort-Object EpgGuida)) {
  $id = $c.EpgId
  if ($c.EpgGuida -gt 0 -and $usati.Contains($id)) { $id = "$id.g$($c.EpgGuida)" }
  $c.Epg = $id; $usati[$id] = $c
  $perGuida["$($c.EpgGuida)|$($c.EpgId)"] = $id
}
$fs = [IO.File]::Create($Guida)
$gz = New-Object IO.Compression.GZipStream($fs, [IO.Compression.CompressionMode]::Compress)
$sw = New-Object IO.StreamWriter($gz, (New-Object Text.UTF8Encoding($false)))
$sw.WriteLine('<?xml version="1.0" encoding="UTF-8"?>')
$sw.WriteLine('<tv generator-info-name="iptv-italia">')
foreach ($id in $usati.Keys) {
  $c = $usati[$id]
  $sw.Write("<channel id=`"$([Security.SecurityElement]::Escape($id))`"><display-name lang=`"it`">$([Security.SecurityElement]::Escape($c.Nome))</display-name>")
  if ($c.Logo) { $sw.Write("<icon src=`"$([Security.SecurityElement]::Escape($c.Logo))`" />") }
  $sw.WriteLine('</channel>')
}
$programmi = 0
foreach ($gu in $guide) {
  foreach ($p in $gu.Xml.tv.programme) {
    $id = $perGuida["$($gu.Indice)|$($p.channel)"]
    if (-not $id -or ($p.stop -and $p.stop.Substring(0, 14) -lt $limite)) { continue }
    $p.SetAttribute('channel', $id)
    $sw.WriteLine($p.OuterXml); $programmi++
  }
}
$sw.WriteLine('</tv>'); $sw.Close()

Write-Host '5/5  Scrivo playlist e rapporto...'
Scrivi-M3U $Uscita $elenco
$nazionali = @($elenco | Where-Object { $_.Chno -lt 9999 })
Scrivi-M3U $UscitaNazionali $nazionali

$md = New-Object Collections.Generic.List[string]
$conEpg = @($elenco | Where-Object { $_.Epg }).Count
$md.Add('# Stato dei canali'); $md.Add('')
$md.Add("Aggiornato il $($oggi.ToString('yyyy-MM-dd')) da ``genera_lista.ps1``.")
$md.Add('')
$md.Add("- **$($elenco.Count)** canali in ``lista_italia.m3u``, **$($nazionali.Count)** con numero LCN in ``lista_nazionali.m3u``")
$md.Add("- **$conEpg** canali con guida EPG ($programmi programmi in ``guida.xml.gz``)")
$md.Add("- Fonti EPG usate: " + (($guide | ForEach-Object { $g = $_; "$($g.Nome) ($(@($elenco | Where-Object { $_.EpgGuida -eq $g.Indice -and $_.Epg }).Count))" }) -join ', '))
$note = @($elenco | Where-Object { $_.Nota -like 'non *' })
if ($note.Count) { $md.Add("- **$($note.Count)** canali tenuti anche se oggi non hanno risposto (tolleranza di $GiorniTolleranza giorni)") }
$md.Add('')
$mancanti = @($LCN.Keys | Where-Object { $n = $_; -not ($nazionali | Where-Object { $_.Chno -eq $n }) } | Sort-Object)
if ($mancanti.Count) {
  $md.Add('## Numeri LCN senza un flusso funzionante'); $md.Add('')
  $md.Add(($mancanti | ForEach-Object { "$_ $(@($LCN[$_])[0])" }) -join ' · ')
  $md.Add('')
}
$senzaLcn = @($elenco | Where-Object { $_.Epg -and $_.Chno -eq 9999 -and $_.Cat -ne 'Rai' })
if ($senzaLcn.Count) {
  $md.Add('## Canali con guida EPG ma senza numero LCN'); $md.Add('')
  $md.Add('Possibili canali nazionali da aggiungere alla tabella `$LCN` dello script:'); $md.Add('')
  $md.Add(($senzaLcn | ForEach-Object { $_.Nome }) -join ' · ')
  $md.Add('')
}
$md.Add('## Elenco'); $md.Add('')
$md.Add('| LCN | Canale | Gruppo | Fonte | EPG | Note |')
$md.Add('|---:|---|---|---|:---:|---|')
foreach ($c in $elenco) {
  $host_ = ([Uri]$c.Url).Host
  $md.Add("| $(if ($c.Chno -lt 9999) { $c.Chno }) | $($c.Nome -replace '\|', '/') | $($c.Cat) | $host_ | $(if ($c.Epg) { '✓' } else { '' }) | $($c.Nota) |")
}
[IO.File]::WriteAllLines($Rapporto, $md, (New-Object Text.UTF8Encoding($false)))

Write-Host ''
Write-Host "Fatto: $($elenco.Count) canali ($($nazionali.Count) nazionali), $conEpg con EPG, $programmi programmi in guida"
$elenco | Group-Object Cat | Sort-Object { [array]::IndexOf($ordineCat, $_.Name) } | ForEach-Object { Write-Host ("  {0,-24} {1,3}" -f $_.Name, $_.Count) }
