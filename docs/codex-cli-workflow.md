# 自分とCodex CLIでTera Termの作業を引き継ぐ

操作画面は、接続済みのTera Termです。Codex CLIは手順をJSONの実行計画にして、連携用PowerShellスクリプト`teraterm_logger.ps1`へ登録します。常駐マクロがそのTera Termで`sendln`によりコマンドを送り、Tera Termが通信・画面表示・ログ記録を担当します。手動操作とCodex CLIに依頼したコマンド・応答が、同じログに残ります。

ユーザーは普段どおりTera Termを起動して接続・ログインします。それとは別に、このリポジトリのフォルダでCodex CLIを起動し、手順書を示して「この手順書の2から3まで、このTera Termで」と依頼します。セッション一覧の確認、JSONの作成、`teraterm_logger.ps1`への登録、進捗と出力の確認はCodex CLIが担当します。ユーザーがJSONを手書きする必要はありません。

```text
ユーザー → Codex CLI → teraterm_logger.ps1 → 常駐マクロ → 接続済みTera Term
```

Codex CLIの導入・起動はユーザー側で行います。teraterm_loggerが提供するのは、依頼を受け付けるPowerShell連携スクリプトと、Tera Term上で実行する常駐マクロです。以下のPowerShellコマンドはCodex CLIが使う連携窓口であり、Codex CLI自体の起動コマンドではありません。

## 1. 対象と現在位置を確認する

ユーザーはTera Termを起動してログインし、普段どおり作業します。Codex CLIは操作を引き継ぐ前に、セッション一覧で接続先とログ保存先を確認します。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\teraterm_logger.ps1 -Action Sessions
```

Codex CLIは依頼された接続先に対応するセッションIDを一つ選びます。複数のTera Termが開いていて対象を特定できない場合は、接続先をユーザーに確認します。`teraterm_logger.ps1`が対象を自動選択することはありません。ログイン途中や確認待ちの画面から開始せず、手順を始められるプロンプトまで進めます。

## 2. 手順と停止位置を決める

Codex CLIへの依頼例です。

> このTera Termの接続先で、手順書の2〜3だけ実行して。まず対象セッション、送信するコマンド、完了とみなすプロンプトを確認して、4以降は実行しないで。タイムアウトしたら再実行せず、そこで状況を知らせて。

Codex CLIは手順書の説明を、そのまま端末へ貼り付けません。実行するコマンドを一つずつ計画にし、選択するセッション・範囲・コマンドが依頼内容と一致することを確認します。実行範囲を省略して全手順を実行する機能はありません。

## 3. 実行計画を用意する

Codex CLIが用意する計画の形式は次のとおりです。これは`mock-device# `というプロンプトを出す模擬端末向けの例です。実機向けのコマンド例ではありません。

```json
{
  "name": "Mock terminal demonstration",
  "steps": [
    {
      "id": 1,
      "label": "Demo step 1",
      "command": "echo DEMO_STEP_1",
      "expect": "(?m)^mock-device# $",
      "timeoutSeconds": 10
    },
    {
      "id": 2,
      "label": "Demo step 2",
      "command": "echo DEMO_STEP_2",
      "expect": "(?m)^mock-device# $",
      "timeoutSeconds": 10
    }
  ]
}
```

| 項目 | 内容 |
| --- | --- |
| `name` | 計画名 |
| `steps[].id` | 手順番号。9桁以内の正の整数を昇順・重複なしで指定 |
| `label` | 履歴で識別できる手順名 |
| `command` | 送信する1行のコマンド。改行・制御文字は禁止 |
| `expect` | 応答完了の目印を表す正規表現 |
| `timeoutSeconds` | 応答待ちの上限。1〜300秒 |

文字列フィールドは各384 UTF-8バイト以内です。1回に選択できる手順は最大100件です。開始・終了の番号は計画内に存在する必要があります。

`expect`は`teraterm_logger.ps1`で.NETの構文検査を行い、実行時はTera Termの正規表現エンジン（Oniguruma）で評価します。両方で使える構文にして、対象機器のプロンプト、モード変更、末尾の空白に合わせてください。例の`(?m)^mock-device# $`は、行頭から行末までが`mock-device# `に一致する行を待ちます。空文字に一致するパターンは使えません。通常のコマンド出力を完了と誤認しないよう、実際のプロンプトを絞り込みます。PowerShell側の構文検査だけでは、Tera Termで動くことの確認にはなりません。

プロンプトが戻るだけでは、コマンドの成功を保証できません。エラー応答でもプロンプトが出る機器があります。確認が必要なところは範囲を区切り、画面・ログの出力を見てから続きの範囲を依頼してください。

ページ送りや対話式の確認があるコマンドは、単純な1行実行とプロンプト待ちだけでは完了しない場合があります。対象機器の操作方法を確認し、この版で扱える手順に分けてください。

## 4. 指定した範囲を実行する

[サンプル計画](../examples/demo-plan.json)のうち、手順2〜3だけを実行する例です。`<session-id>`は一覧で確認したIDに置き換えます。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\teraterm_logger.ps1 -Action Run -SessionId <session-id> -PlanPath .\examples\demo-plan.json -FromStep 2 -ToStep 3
```

`teraterm_logger.ps1 -Action Run`は依頼を登録して終了します。Codex CLIは続けて`Status`で状態を確認します。コマンド送信は常駐マクロが行い、Tera Term上でコマンドと応答を確認できます。タイトルとローカルの実行マーカーにも進捗が表示されます。マーカーは接続先へ送るコマンドではありません。

依頼を登録できたことと、実行を完了したことは別です。状態を確認します。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\teraterm_logger.ps1 -Action Status -SessionId <session-id>
```

指定した終了手順の応答を確認すると、常駐マクロは後続を送らず手動操作へ戻ります。手順4へ勝手に進むことはありません。Codex CLIは最後に送信した手順、応答を確認できた範囲、ログの場所、残っている手順を伝えて引き継ぎます。

## 5. 途中停止・タイムアウト・切断

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\teraterm_logger.ps1 -Action Stop -SessionId <session-id>
```

`Stop`は後続の手順を止める依頼です。送信済みのコマンドを取り消したり、接続先の処理を中断したりはしません。現在のプロンプト待ちが終わるかタイムアウトするまで、処理中として扱います。

タイムアウトや切断で止まった場合、接続先ではコマンドが完了していることもあります。「失敗したからもう一度」と自動送信せず、Tera Termとログで状態を確認してください。必要ならTera Term上で機器に適した中断操作を行います。Codex CLIに依頼した手順の実行中に並行して入力すると、手順と応答の対応が分からなくなるため、手動への引き継ぎを確認してから操作します。

タイムアウト・エラー後は新しい`Run`を拒否します。Codex CLIとユーザーが画面・ログで送信済みコマンドの結果と現在のプロンプトを確認したら、Codex CLIは次の操作で確認済みとして待機状態へ戻します。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\teraterm_logger.ps1 -Action Acknowledge -SessionId <session-id>
```

`Acknowledge`はコマンドを再送しません。同じTera Termとログを保ったまま、次に実行する範囲を明示した新しい`Run`を登録できます。依頼の待機中・実行中には使えません。切断したセッションは復帰や再実行の対象にせず、再接続後に新しいロガーセッションを開始します。

履歴は既定で`%LOCALAPPDATA%\teraterm_logger`、端末ログはドキュメント内の`TeraTermLogs`に残ります。ログには手入力の内容や接続先の応答も含まれるため、共有する前に内容を確認してください。
