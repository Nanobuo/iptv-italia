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

## Rigenerare la lista

I link cambiano spesso. Lo script scarica le sorgenti, verifica che ogni flusso risponda, elimina i doppioni, abbina l'EPG e scrive `lista_italia.m3u`:

```powershell
powershell -ExecutionPolicy Bypass -File genera_lista.ps1
```

Opzioni:

- `-Backup`: aggiunge i flussi alternativi funzionanti dello stesso canale
- `-NoCheck`: salta la verifica dei flussi (più veloce, ma include link morti)
- `-Uscita <file>`: percorso del file da generare

Richiede Windows PowerShell 5.1 o successivo.

## Sorgenti

- [Free-TV/IPTV](https://github.com/Free-TV/IPTV): solo canali free-to-air
- [iptv-org/iptv](https://github.com/iptv-org/iptv): emittenti locali e regionali
- [epgshare01](https://epgshare01.online): guida EPG

Questo repository non ospita alcun contenuto video: contiene solo link a flussi pubblici e gratuiti messi a disposizione dalle emittenti stesse.
