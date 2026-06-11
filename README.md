# teraterm_logger

Tera Term を起動して接続したあと、1画面でログ保存先とログファイル名を決めて `logopen` するためのマクロです。

## 使い方

### 通常起動で毎回動かす

次の3ファイルを同じフォルダに置きます。

```text
auto_log_prompt.ttl
log_prompt.ps1
log_categories.txt
```

Tera Term 5 では、相対パス指定のマクロは `%APPDATA%\teraterm5\` から探されます。
そのため、次の配置にしておくのが一番ラクです。

```text
%APPDATA%\teraterm5\auto_log_prompt.ttl
%APPDATA%\teraterm5\log_prompt.ps1
%APPDATA%\teraterm5\log_categories.txt
```

そのうえで `%APPDATA%\teraterm5\TERATERM.INI` の `[Tera Term]` セクションに次を設定します。

```ini
StartupMacro=auto_log_prompt.ttl
HostDialogOnStartup=off
```

これで通常どおり Tera Term を起動したときに、このマクロが自動実行されます。
`HostDialogOnStartup=off` にしているのは、接続ダイアログをこのマクロ側で出すためです。

### フルパスで指定する場合

```ini
StartupMacro=C:\project\teraterm_logger\auto_log_prompt.ttl
HostDialogOnStartup=off
```

この場合も、`auto_log_prompt.ttl` と同じフォルダに `log_prompt.ps1` と `log_categories.txt` を置いてください。

### コマンドラインで試す場合

```bat
ttermpro.exe /M=C:\project\teraterm_logger\auto_log_prompt.ttl
```

## 動き

- 未接続なら Tera Term の新規接続ダイアログを出します。
- 接続できたら、ログ設定画面を1つだけ出します。
- ログ設定画面では、保存先フォルダ、サブ要素、ログファイル名を指定できます。
- ログファイル名の初期値は `yyyyMMdd_保存先フォルダ名_サブ要素.log` です。
- サブ要素を変えると、ログファイル名も自動で更新されます。
- ログファイル名は手動編集できます。
- 既に同名ファイルがある場合、初期値には `_001`, `_002` のような連番を付けます。
- OK すると `logopen` でログ取得を開始します。
- Cancel した場合、ログなしでそのまま終了します。

## サブ要素の編集

ドロップダウンの候補は `log_categories.txt` で管理しています。
1行に1候補を書いてください。

```text
テスト
検証
インストール
調査
障害対応
作業
その他
```

## メモ

`logopen` は通常のテキストログとして開始し、ログダイアログは隠します。
マクロ自体はログ開始後に終了しますが、Tera Term 側のログ取得はセッション終了まで続きます。

Tera Term は `ttermpro.exe` と同じフォルダに `portable.ini` がある場合、ポータブル版として動き、設定ファイルの保存先も実行ファイル側になります。
ただし通常の `C:\Program Files\...` 配下は書き込み権限で詰まりやすいので、このマクロだけを自動実行したい場合は `%APPDATA%\teraterm5\` 配下の利用を推奨します。
