# teraterm_logger

[Esperanto](README.md) / 日本語

**ログの名前と保存は自動にして、作業は自分もCodex CLIも同じTera Termで進める**ためのツールです。Codex CLIに任せる手順を番号で指定すると、開いているTera Termにコマンドを送り、指定範囲で止まります。

- 接続後、保存先やファイル名を選ばずログ取得を開始します。
- 手作業の入力とCodex CLIに依頼した実行内容・応答を、同じ画面とログで確認できます。
- Codex CLIには開始手順と終了手順を両方指定します。範囲外の手順は実行しません。
- Tera Termのタイトルと実行履歴で、手動操作中かCodex CLIに依頼した何番の手順かを確認できます。

対象はWindows / Tera Term 5 / Windows PowerShell 5.1です。

設置後は下記の起動用ショートカットからTera Termを開き、普段どおり接続・ログインします。別途、ユーザーがこのリポジトリのフォルダでCodex CLIを起動し、手順書を示して次のように頼みます。

> この手順書の2から3まで、このTera Termで実行して。3が終わったら止めて、自分に戻して。

Codex CLIが対象セッションを確認し、必要な実行計画を作成・登録して、最後にどこまで進んだかを伝えます。JSONの作成と連携用PowerShellスクリプトの操作はCodex CLIが担当するので、ユーザーがJSONを手書きする必要はありません。

| 担当 | 役割 |
| --- | --- |
| ユーザー | Tera Termで接続・ログインし、別途起動したCodex CLIへ手順書と実行範囲を伝える |
| Codex CLI | 手順をJSONの実行計画にし、`teraterm_logger.ps1`へ登録して進捗・出力を確認する |
| `teraterm_logger.ps1` | ローカルの連携窓口として、セッション確認・依頼登録・状態確認を受け付ける |
| 常駐Tera Termマクロ | 既存のTera Termで`sendln`によりコマンドを送信し、指定範囲で止まる |
| Tera Term | 接続先との通信、画面表示、端末ログの記録を行う |

Codex CLIの導入・起動はユーザー側で行います。このツールが提供するのは、Codex CLIの依頼を受け付けるPowerShell連携スクリプトと、Tera Term上で実行する常駐マクロです。

## 設置と起動

次の3ファイルを同じフォルダに置きます。

```text
auto_log_prompt.ttl
teraterm_logger.ps1
TeratermLogger.psm1
```

### 推奨：マクロを起動するショートカットを使う

次の内容をリンク先にしたWindowsのショートカットを作成し、普段の起動に使います。Tera Termのインストール先とマクロの配置先は、実際の場所に合わせてください。

```bat
"C:\Program Files\teraterm5\ttpmacro.exe" /V "C:\tools\teraterm_logger\auto_log_prompt.ttl"
```

マクロを先に起動し、そのマクロがTera Termを開きます。毎回ロガーを入口にするため、`TERATERM.INI`を編集せずに自動ログを使えます。`/V`はマクロの制御ウィンドウを隠す指定です。Tera Termの操作画面と「新しい接続」画面は表示されます。

タスクバーから起動する場合は、このショートカットをピン留めしてください。ショートカットのアイコンは、Tera Term本体の`ttermpro.exe`から選べます。

接続・ログインは普段どおりTera Termで行います。接続画面をキャンセルした場合もマクロは待機するので、「ファイル」→「新しい接続」から接続できます。接続が完了すると自動でログ取得を始めます。

### Tera Term本体から起動する場合（任意）

`ttermpro.exe`から起動したい場合は、自分が使う`TERATERM.INI`の`[Tera Term]`セクションに設定します。通常のTera Term 5では`%APPDATA%\teraterm5\TERATERM.INI`です。ポータブル版や`/F=`で設定ファイルを指定している場合は、その設定ファイルを使ってください。

```ini
StartupMacro=C:\tools\teraterm_logger\auto_log_prompt.ttl
HostDialogOnStartup=on
```

この設定で起動したマクロも、未接続のときは「新しい接続」画面を開きます。本体のコマンドラインでマクロを指定する場合は、次のように起動できます。

```bat
"C:\Program Files\teraterm5\ttermpro.exe" /M="C:\tools\teraterm_logger\auto_log_prompt.ttl"
```

マクロは接続後も常駐します。常駐中のマクロを終了するとCodex CLIからの実行依頼を受け取れなくなります。

## ログはどこに保存されるか

既定の保存先はWindowsの「ドキュメント」フォルダ内です。ドキュメントをOneDriveなどへ移動している場合、その移動先を使います。

```text
Documents\TeraTermLogs\yyyy-MM-dd\timestamp_host_unique.log
```

日付、時刻、接続先、一意な識別子から名前を自動生成します。同時に複数の接続を開いても、別々のセッションとログになります。

保存先を変える場合は`%LOCALAPPDATA%\teraterm_logger\config.json`を作成します。初回接続前でも作成できます。

```json
{
  "LogRoot": "D:\\TerminalLogs"
}
```

次に起動するセッションから反映されます。設定・セッション状態・手順履歴は`%LOCALAPPDATA%\teraterm_logger`に保存します。環境変数`TERATERM_LOGGER_HOME`で別の状態フォルダを指定できます。Tera Termと、Codex CLIから呼び出す`teraterm_logger.ps1`の両方で同じ設定を使ってください。`teraterm_logger.ps1`だけの`-StateRoot`指定も可能です。

## Codex CLIに手順の一部を任せる

詳しい引き継ぎ方法は[Codex CLIとの作業手順](docs/codex-cli-workflow.md)にあります。

1. Tera Termで対象機器に接続し、ログインと現在の状態を確認します。
2. 別途Codex CLIを起動し、手順書と実行する範囲・停止位置を伝えます。
3. Codex CLIがJSON形式の実行計画を作り、`teraterm_logger.ps1`で対象セッションと番号の範囲を指定して依頼します。
4. コマンドと応答がTera Termに表示されます。指定範囲を終えると手動操作に戻ります。

### Codex CLIが使う連携コマンド

以下はCodex CLIが呼び出す`teraterm_logger.ps1`のコマンド例です。Codex CLI自体の起動コマンドではありません。リポジトリのフォルダから、まず接続中のセッションを確認します。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\teraterm_logger.ps1 -Action Sessions
```

接続先・ログ保存先を確認し、表示されたセッションIDを明示して実行します。次は手順2から3だけを実行する例です。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\teraterm_logger.ps1 -Action Run -SessionId <session-id> -PlanPath .\examples\demo-plan.json -FromStep 2 -ToStep 3
```

`<session-id>`は実際のIDに置き換えてください。サンプル計画は模擬接続専用です。実機で使う前に、コマンドとプロンプトの正規表現を対象機器に合わせる必要があります。

進捗確認と、途中で次の手順へ進まないようにする操作は次のとおりです。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\teraterm_logger.ps1 -Action Status -SessionId <session-id>
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\teraterm_logger.ps1 -Action Stop -SessionId <session-id>
```

`Run`は実行依頼を登録します。完了確認には`Status`を使います。実際のコマンド送信は、そのセッションに接続されたTera Termマクロの`sendln`で行います。通信とログ記録は同じTera Termが担当します。

## 停止と引き継ぎの注意

- `Stop`は次の手順へ進むのを止めます。送信済みのコマンドは中断しません。現在の応答待ちが終わるかタイムアウトしたあとで手動操作へ戻ります。
- 今動いているコマンドを止めたい場合は、Tera Term上で対象機器に適した操作をしてください。たとえば`Ctrl+C`が有効な機器では、それを使えます。
- タイムアウトや切断時は後続コマンドを送りません。送信済みコマンドの処理結果は不明として扱い、画面とログを確認します。自動再実行はしません。
- `expect`への一致は応答の区切りを示します。コマンドの成功や設定の正しさを保証するものではありません。
- Codex CLIに依頼した手順を実行している間は、同じ端末へ並行して入力しないでください。結果を確認してから操作を引き継ぎます。

タイムアウトやエラー後は、新しい`Run`を受け付けません。Tera Termで実際の処理結果と現在のプロンプトを確認したあと、次の操作で待機状態へ戻せます。コマンドの再送は行わず、ログは同じセッションで継続します。その後、必要な範囲を改めて指定して依頼します。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\teraterm_logger.ps1 -Action Acknowledge -SessionId <session-id>
```

依頼の待機中・実行中は`Acknowledge`できません。切断したセッションは復帰・再実行できないため、再接続後は新しいロガーセッションを開始します。

以前の保存先・分類選択用`log_prompt.ps1`と`log_categories.txt`は旧方式の補助ファイルです。新しい起動マクロはそれらを使いません。
