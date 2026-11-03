# Lista IPTV Italia – canali in chiaro con EPG

Playlist M3U con i canali televisivi italiani **in chiaro (free-to-air)** trasmessi in streaming ufficiale dalle emittenti, con guida elettronica dei programmi (EPG) già collegata.

## Uso

Aggiungi al tuo player IPTV (TiviMate, Kodi PVR IPTV Simple, VLC, MPV…) l'URL di una delle due playlist:

| Playlist | Contenuto | URL |
|---|---|---|
| Completa | tutti i canali, comprese emittenti locali e radio | `https://raw.githubusercontent.com/Nanobuo/iptv-italia/main/lista_italia.m3u` |
| Nazionali | solo i canali con numero LCN nazionale | `https://raw.githubusercontent.com/Nanobuo/iptv-italia/main/lista_nazionali.m3u` |

L'EPG viene caricato automaticamente dall'intestazione della playlist. Se il tuo player non lo fa, impostalo a mano:

```
https://github.com/Nanobuo/iptv-italia/releases/download/dati/guida.xml.gz
```

La guida contiene solo i canali della lista e unisce più fonti gratuite. Per la maggior parte delle emittenti locali non esiste una guida gratuita.

Lo stato aggiornato di ogni canale (fonte usata, guida, eventuali problemi) è in [STATO.md](STATO.md).

## Contenuto

| Gruppo | Esempi |
|---|---|
| Rai | Rai 1–5, Rai Movie, Rai Premium, Rai News 24, Rai Storia, Rai Sport… |
| Mediaset | Rete 4, Canale 5, Italia 1, 20, Iris, La 5, Cine34, Focus, Top Crime, TGCom 24… |
| Nazionali | La7, TV8, Nove, Cielo, Real Time, DMAX, Giallo, Super!, HGTV… |
| Notizie, Sport, Bambini | Sky TG24, Sportitalia, SuperTennis, Rai Gulp, Rai YoYo… |
| Musica e Radiovisione | RTL 102.5, Radio 105, Deejay TV, Virgin Radio, RDS… |
| Istituzionali | Camera dei Deputati, Senato |
| Locali e altri | Emittenti regionali e locali |

I canali Rai usano i flussi ufficiali Rai, in 1080p dove Rai lo trasmette (Rai 1, Rai 2, Rai 3, Rai Sport). Funzionano nei lettori installati (VLC, MPV, Kodi, TiviMate…) ma non in quelli che girano nel browser. Alcuni flussi, soprattutto Rai e Mediaset, sono visibili solo da connessioni italiane.

I canali nazionali hanno la **numerazione LCN italiana** del digitale terrestre (Rai 1 = 1, Canale 5 = 5, La7 = 7, Rai 4 = 21, Real Time = 31, DMAX = 52…), quindi nel player compaiono nello stesso ordine del telecomando. Le emittenti locali, la cui numerazione cambia da regione a regione, sono in fondo senza numero.

## Aggiornamento automatico

Ogni notte GitHub Actions ([`aggiorna-lista.yml`](.github/workflows/aggiorna-lista.yml)) rigenera playlist, guida e rapporto e li pubblica. Gli URL restano sempre gli stessi. Si può avviare anche a mano dalla scheda **Actions** → **Aggiorna lista** → **Run workflow**.

- I server di GitHub sono fuori dall'Italia, quindi lì lo script gira con `-TieniGeo`: i flussi segnalati come geobloccati vengono mantenuti senza verificarli. Lo stesso vale per i server che rispondono solo dall'Italia senza essere segnalati, elencati in `$HOST_SOLO_ITALIA` nello script.
- Un flusso che una notte non risponde resta in lista se ha funzionato negli ultimi 3 giorni, così un guasto passeggero non fa sparire il canale. La data dell'ultima risposta di ogni flusso è in `stato.json`.
- Guida (`guida.xml.gz`) e stato (`stato.json`) sono pubblicati nella release [`dati`](https://github.com/Nanobuo/iptv-italia/releases/tag/dati), per non appesantire il repository.

## Rigenerare la lista a mano

Lo script scarica le sorgenti, verifica che ogni flusso risponda, elimina i doppioni, abbina l'EPG e scrive playlist, guida e rapporto:

```powershell
powershell -ExecutionPolicy Bypass -File genera_lista.ps1
```

Opzioni:

- `-Backup`: aggiunge i flussi alternativi funzionanti dello stesso canale
- `-NoCheck`: salta la verifica dei flussi (più veloce, ma include link morti)
- `-TieniGeo`: tiene i flussi geobloccati senza verificarli (per l'uso fuori dall'Italia)
- `-GiorniTolleranza <n>`: giorni in cui un flusso che non risponde resta in lista (predefinito 3)
- `-MinCanali <n>`: non sovrascrive la lista se ne escono meno di `n` canali (predefinito 150)
- `-Uscita`, `-UscitaNazionali`, `-Guida`, `-Rapporto`, `-Stato`: percorsi dei file generati

Richiede Windows PowerShell 5.1 o successivo.

La numerazione LCN è nella tabella `$LCN` all'inizio dello script. [STATO.md](STATO.md) segnala i numeri LCN senza un flusso funzionante e i canali con guida ma senza numero, possibili canali nazionali da aggiungere.

## Sorgenti

- [Free-TV/IPTV](https://github.com/Free-TV/IPTV): solo canali free-to-air
- [iptv-org/iptv](https://github.com/iptv-org/iptv): emittenti locali e regionali
- Guida EPG: [epgshare01](https://epgshare01.online), [open-epg.com](https://www.open-epg.com), [iptv-epg.org](https://iptv-epg.org)

Questo repository non ospita alcun contenuto video: contiene solo link a flussi pubblici e gratuiti messi a disposizione dalle emittenti stesse.
