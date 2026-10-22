# Lista IPTV Italia – canali in chiaro con EPG

Playlist M3U con i canali televisivi italiani **in chiaro (free-to-air)** trasmessi in streaming ufficiale dalle emittenti, con guida elettronica dei programmi (EPG) già collegata.

## Uso

Aggiungi al tuo player IPTV (TiviMate, IPTV Smarters, Kodi PVR IPTV Simple, VLC…) l'URL della playlist:

```
https://raw.githubusercontent.com/Nanobuo/iptv-italia/main/lista_italia.m3u
```

L'EPG viene caricato automaticamente dall'intestazione della playlist. Se il tuo player non lo fa, impostalo a mano:

```
https://epgshare01.online/epgshare01/epg_ripper_IT1.xml.gz
```

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

Alcuni flussi (soprattutto Rai e Mediaset) sono visibili solo da connessioni italiane.

### Canali Rai e voci "alternativo"

Per i canali Rai la lista usa il flusso ufficiale Rai, il più stabile. Il server Rai però accetta solo alcuni user-agent: la lista dichiara quello di un browser con `#EXTVLCOPT`, che VLC, Kodi e TiviMate rispettano. I player che non lo fanno, come IPTVnator, ricevono un errore. Per loro ogni canale Rai ha anche una voce **"(alternativo)"**, che punta a una ritrasmissione di terzi.

In alternativa, nelle impostazioni della playlist di IPTVnator si può impostare questo user-agent:

```
Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36
```

I canali nazionali hanno la **numerazione LCN italiana** del digitale terrestre (Rai 1 = 1, Canale 5 = 5, La7 = 7, Rai 4 = 21, Real Time = 31, DMAX = 52…), quindi nel player compaiono nello stesso ordine del telecomando. Le emittenti locali, la cui numerazione cambia da regione a regione, sono in fondo senza numero.

## Aggiornamento automatico

Ogni notte GitHub Actions ([`aggiorna-lista.yml`](.github/workflows/aggiorna-lista.yml)) rigenera la lista e, se è cambiata, la pubblica. L'URL della playlist resta sempre lo stesso. Si può avviare anche a mano dalla scheda **Actions** → **Aggiorna lista** → **Run workflow**.

I server di GitHub sono fuori dall'Italia, quindi lì lo script gira con `-TieniGeo`: i flussi segnalati come geobloccati vengono mantenuti senza verificarli.

## Rigenerare la lista a mano

I link cambiano spesso. Lo script scarica le sorgenti, verifica che ogni flusso risponda, elimina i doppioni, abbina l'EPG e scrive `lista_italia.m3u`:

```powershell
powershell -ExecutionPolicy Bypass -File genera_lista.ps1
```

Opzioni:

- `-Backup`: aggiunge i flussi alternativi funzionanti dello stesso canale
- `-NoCheck`: salta la verifica dei flussi (più veloce, ma include link morti)
- `-TieniGeo`: tiene i flussi geobloccati senza verificarli (per l'uso fuori dall'Italia)
- `-MinCanali <n>`: non sovrascrive la lista se ne escono meno di `n` canali (predefinito 150)
- `-Uscita <file>`: percorso del file da generare

Richiede Windows PowerShell 5.1 o successivo.

## Sorgenti

- [Free-TV/IPTV](https://github.com/Free-TV/IPTV): solo canali free-to-air
- [iptv-org/iptv](https://github.com/iptv-org/iptv): emittenti locali e regionali
- [epgshare01](https://epgshare01.online): guida EPG

Questo repository non ospita alcun contenuto video: contiene solo link a flussi pubblici e gratuiti messi a disposizione dalle emittenti stesse.
