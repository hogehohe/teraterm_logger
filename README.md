# teraterm_logger

Esperanto / [日本語](README.ja.md)

**Aŭtomata protokolado kaj kunlaboro kun Codex CLI en la sama videbla Tera Term-fenestro.** La uzanto plu laboras en Tera Term; Codex CLI povas peti rulon de nur eksplicite elektita intervalo de paŝoj kaj poste redoni la regadon.

Por Windows, Tera Term 5 kaj Windows PowerShell 5.1.

Post instalado, la uzanto malfermas Tera Term, konektiĝas kaj ensalutas kiel kutime. Aparte, la uzanto lanĉas Codex CLI en la dosierujo de ĉi tiu deponejo kaj donas al ĝi la proceduron kaj petitan intervalon, ekzemple paŝojn 2 ĝis 3 en tiu Tera Term-fenestro. Codex CLI kontrolas la celan seancon, preparas la JSON-planon, registras la elektitan intervalon per `teraterm_logger.ps1` kaj raportas la progreson. La uzanto ne devas mane verki JSON.

| Partoprenanto | Rolo |
| --- | --- |
| Uzanto | Konektiĝas kaj ensalutas en Tera Term, aparte lanĉas Codex CLI kaj donas la proceduron kaj intervalon |
| Codex CLI | Preparas la JSON-planon, vokas `teraterm_logger.ps1` kaj kontrolas progreson kaj eligon |
| `teraterm_logger.ps1` | Loka PowerShell-interfaco por listigi seancojn, registri petojn kaj kontroli staton |
| Loĝanta Tera Term-makroo | Sendas komandojn per `sendln` en la jam malfermita Tera Term kaj haltas ĉe la elektita limo |
| Tera Term | Prizorgas la konekton, videblan terminalon kaj protokoladon |

La uzanto aparte instalas kaj lanĉas Codex CLI. Ĉi tiu ilo liveras la PowerShell-interfacon, kiu akceptas ĝiajn petojn, kaj la loĝantan Tera Term-makroon, kiu plenumas la elektitajn paŝojn. La sekvaj PowerShell-komandoj estas la interfaco vokata de Codex CLI, ne komandoj por lanĉi Codex CLI.

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

Agordoj, seancostatoj kaj paŝhistorio troviĝas en `%LOCALAPPDATA%\teraterm_logger`. La mediovariablo `TERATERM_LOGGER_HOME` povas ŝanĝi tiun lokon; uzu la saman valoron por Tera Term kaj `teraterm_logger.ps1`, kiun vokas Codex CLI. `teraterm_logger.ps1` ankaŭ akceptas `-StateRoot`.

## Peti al Codex CLI ruli elektitajn paŝojn

Codex CLI unue listigas la seancojn per la PowerShell-interfaco kaj kontrolas la celon:

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

`Run` registras peton; `Status` montras ĝian progreson. La loĝanta makroo sendas la komandojn per `sendln` en la jam malfermita Tera Term. La sama Tera Term prizorgas la konekton kaj protokolon. La fenestra titolo, videblaj markiloj kaj loka historio helpas sekvi la transdonon inter la uzanto kaj Codex CLI.

`Stop` haltigas antaŭ la sekva paŝo; ĝi ne interrompas jam senditan komandon. Post tempolimo aŭ malkonekto, ne pluaj komandoj estas sendataj, kaj la rezulto de la nuna paŝo restas necerta. Ne estas aŭtomata ripeto. Kongruo kun `expect` nur markas la finon de respondo, ne pruvas sukceson. Ne tajpu samtempe dum la paŝoj petitaj de Codex CLI ruliĝas.

Post tempolimo aŭ eraro, nova `Run` estas rifuzata ĝis kontrolo de la rezulto kaj nuna terminala invito. Poste Codex CLI povas konfirmi la kontrolon per:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\teraterm_logger.ps1 -Action Acknowledge -SessionId <session-id>
```

Tio revenigas la seancon al atendado sen resendi komandon; la sama protokolo daŭras. Poste eblas eksplicite elekti novan intervalon. `Acknowledge` ne funkcias dum peto atendas aŭ ruliĝas. Malkonektita seanco ne povas esti reaktivigita aŭ reludita; post rekonekto komencu novan protokolan seancon.

La [japana gvidilo pri kunlaboro kun Codex CLI](docs/codex-cli-workflow.md) klarigas la planformaton kaj transdonon. La malnova `log_prompt.ps1` kaj `log_categories.txt` restas por la antaŭa dialoga maniero; la nova startmakroo ne uzas ilin.
