# teraterm_logger

Esperanto / [日本語](README.ja.md)

Malgranda makroo por Tera Term, kiu post konektiĝo montras unu fenestron por elekti la dosierujon kaj dosiernomon de la protokolo, poste startigas `logopen`.

## Uzado

### Aŭtomate ruli ĉe normala startigo

Metu la jenajn tri dosierojn en la saman dosierujon.

```text
auto_log_prompt.ttl
log_prompt.ps1
log_categories.txt
```

En Tera Term 5, makroo kun relativa vojo estas serĉata el `%APPDATA%\teraterm5\`.
Tial la plej simpla aranĝo estas:

```text
%APPDATA%\teraterm5\auto_log_prompt.ttl
%APPDATA%\teraterm5\log_prompt.ps1
%APPDATA%\teraterm5\log_categories.txt
```

Poste aldonu la jenon al la sekcio `[Tera Term]` en `%APPDATA%\teraterm5\TERATERM.INI`.

```ini
StartupMacro=auto_log_prompt.ttl
HostDialogOnStartup=off
```

Tiam la makroo ruliĝos aŭtomate kiam vi startigas Tera Term normale.
`HostDialogOnStartup=off` estas uzata ĉar la konekta dialogo estas malfermita de ĉi tiu makroo.

### Se vi volas uzi plenan vojon

```ini
StartupMacro=C:\project\teraterm_logger\auto_log_prompt.ttl
HostDialogOnStartup=off
```

Ankaŭ en ĉi tiu kazo metu `log_prompt.ps1` kaj `log_categories.txt` en la saman dosierujon kiel `auto_log_prompt.ttl`.

### Provi per komandlinio

```bat
ttermpro.exe /M=C:\project\teraterm_logger\auto_log_prompt.ttl
```

## Konduto

- Se Tera Term ankoraŭ ne estas konektita, ĝi malfermas la dialogon por nova konekto.
- Post konektiĝo, ĝi montras unu fenestron por agordi la protokolon.
- En tiu fenestro vi povas elekti dosierujon, subelementon kaj dosiernomon.
- La komenca dosiernomo estas `yyyyMMdd_dosierujnomo_subelemento.log`.
- Kiam vi ŝanĝas la subelementon, la dosiernomo aŭtomate refreŝiĝas.
- La dosiernomo ankaŭ povas esti mane redaktita.
- Se samnoma dosiero jam ekzistas, la komenca nomo ricevas sufikson kiel `_001` aŭ `_002`.
- Premante OK, la makroo startigas protokoladon per `logopen`.
- Premante Cancel, la makroo finiĝas sen protokolado.

## Redakti subelementojn

La elektoj en la falmenuo estas administrataj per `log_categories.txt`.
Skribu unu elekton en ĉiu linio.

```text
テスト
検証
インストール
調査
障害対応
作業
その他
```

## Notoj

`logopen` startas normalan tekstan protokolon kaj kaŝas la protokolan dialogon.
La makroo mem finiĝas post startigo de protokolado, sed Tera Term daŭre konservas la protokolon ĝis la seanco finiĝas.

Se `portable.ini` troviĝas en la sama dosierujo kiel `ttermpro.exe`, Tera Term funkcias kiel portebla versio, kaj ĝiaj agordaj dosieroj estas konservataj ĉe la ekzekutebla dosiero.
Tamen, en kutima instalado sub `C:\Program Files\...`, skribpermesoj ofte kaŭzas ĝenojn, do por ĉi tiu makroo rekomendindas uzi `%APPDATA%\teraterm5\`.
