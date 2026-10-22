# teraterm_logger

Esperanto / [日本語](README.ja.md)

**Aŭtomata protokolado kaj kunlaboro kun AI en la sama videbla Tera Term-fenestro.** La uzanto plu laboras en Tera Term; AI povas sendi nur eksplicite elektitan intervalon de paŝoj kaj poste redoni la regadon.

Por Windows, Tera Term 5 kaj Windows PowerShell 5.1.

Post instalado, la uzanto nur malfermas Tera Term, konektiĝas kaj petas AI ruli ekzemple paŝojn 2 ĝis 3 en tiu fenestro. AI kontrolas la celan seancon, preparas la JSON-planon, registras la elektitan intervalon kaj raportas la progreson. La sekvaj komandliniaj ekzemploj estas la interfaco uzata de AI.

## Instalado

Metu ĉi tiujn dosierojn en la saman dosierujon:

```text
auto_log_prompt.ttl
teraterm_logger.ps1
TeratermLogger.psm1
```

En la sekcio `[Tera Term]` de via `TERATERM.INI`, agordu:

```ini
StartupMacro=C:\tools\teraterm_logger\auto_log_prompt.ttl
HostDialogOnStartup=off
```

La ordinara loko por Tera Term 5 estas `%APPDATA%\teraterm5\TERATERM.INI`. Por portebla instalado aŭ aparta agorddosiero, uzu ties efektivan lokon. La makroo malfermas la konektan dialogon se necese. Konektiĝu kaj ensalutu kiel kutime; lasu la makroon funkcii dum la seanco.

Por provi sen ŝanĝi la agorddosieron:

```bat
"C:\Program Files\teraterm5\ttermpro.exe" /M="C:\tools\teraterm_logger\auto_log_prompt.ttl"
```

## Aŭtomataj protokoloj

Ne necesas elekti dosiernomon aŭ konservolokon ĉe ĉiu konekto. La defaŭlta loko estas:

```text
Documents\TeraTermLogs\yyyy-MM-dd\timestamp_host_unique.log
```

La vera Windows-dosierujo Documents estas uzata, ankaŭ kiam ĝi estas alilokigita. Por alia loko, kreu `%LOCALAPPDATA%\teraterm_logger\config.json` antaŭ la sekva seanco:

```json
{ "LogRoot": "D:\\TerminalLogs" }
```

Agordoj, seancostatoj kaj paŝhistorio troviĝas en `%LOCALAPPDATA%\teraterm_logger`. La mediovariablo `TERATERM_LOGGER_HOME` povas ŝanĝi tiun lokon; uzu la saman valoron por Tera Term kaj la komandlinia ilo. La ilo ankaŭ akceptas `-StateRoot`.

## Ruli elektitajn paŝojn

Unue listigu la seancojn kaj kontrolu la celon:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\teraterm_logger.ps1 -Action Sessions
```

Post kontrolo de la plano, rulu nur la petitan intervalon. Ambaŭ limoj estas devigaj:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\teraterm_logger.ps1 -Action Run -SessionId <session-id> -PlanPath .\examples\demo-plan.json -FromStep 2 -ToStep 3
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\teraterm_logger.ps1 -Action Status -SessionId <session-id>
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\teraterm_logger.ps1 -Action Stop -SessionId <session-id>
```

Anstataŭigu `<session-id>` per la efektiva ID. La ekzempla plano estas nur por simulita konekto: adaptu ĝiajn komandojn kaj la atendatan terminalan inviton antaŭ uzo kun vera aparato.

`Run` registras peton; `Status` montras ĝian progreson. La loĝanta makroo sendas la komandojn per `sendln` en la jam malfermita Tera Term. Ĝi ne uzas apartan SSH-konekton. La fenestra titolo, videblaj markiloj kaj loka historio helpas sekvi la transdonon inter homo kaj AI.

`Stop` haltigas antaŭ la sekva paŝo; ĝi ne interrompas jam senditan komandon. Post tempolimo aŭ malkonekto, ne pluaj komandoj estas sendataj, kaj la rezulto de la nuna paŝo restas necerta. Ne estas aŭtomata ripeto. Kongruo kun `expect` nur markas la finon de respondo, ne pruvas sukceson. Ne tajpu samtempe dum AI rulas komandojn.

Post tempolimo aŭ eraro, nova `Run` estas rifuzata ĝis kontrolo de la rezulto kaj nuna terminala invito. Poste AI povas konfirmi la kontrolon per:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\teraterm_logger.ps1 -Action Acknowledge -SessionId <session-id>
```

Tio revenigas la seancon al atendado sen resendi komandon; la sama protokolo daŭras. Poste eblas eksplicite elekti novan intervalon. `Acknowledge` ne funkcias dum peto atendas aŭ ruliĝas. Malkonektita seanco ne povas esti reaktivigita aŭ reludita; post rekonekto komencu novan protokolan seancon.

La [japana laborflua gvidilo](docs/ai-workflow.md) klarigas la planformaton kaj transdonon. La malnova `log_prompt.ps1` kaj `log_categories.txt` restas por la antaŭa dialoga maniero; la nova startmakroo ne uzas ilin.
