# 分割払い計算（macOS / iPadOS）

分割払いの条件を計算し、患者に見せながら説明するためのアプリです。
計算結果は自作のHTMLテンプレートで「お支払い予定表」（PDF／印刷）として出力できます。
仕様は [`docs/spec.md`](docs/spec.md)、実装上の決めごとは [`CLAUDE.md`](CLAUDE.md) を参照してください。

## ビルド方法（Mac）

必要なもの: Xcode 15 以降、[XcodeGen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）

```sh
xcodegen generate
open InstallmentCalculator.xcodeproj
```

Xcode で `InstallmentCalculator` スキームを開き、実行先に「My Mac」または iPad（実機・シミュレータ）を選んで実行します。
初回は Signing & Capabilities で自分の Team を選んでください。

対象OS: macOS 14 以降、iPadOS 17 以降。

### テスト

計算・設定・テンプレート処理は `InstallmentKit`（Swift Package）にまとめてあり、Xcode なしでもテストできます。

```sh
cd InstallmentKit
swift test
```

## 使い方

1. 計算モードを選ぶ（① 月額から回数を求める／② 回数から月額を求める）
2. 支払総額・年率・分割回数（または月額）を入れる。入力するとすぐ計算されます
3. 必要ならボーナス払い（加算額・月）、初回支払月、患者名を入れる
4. 結果は大きく表示されます。利息総額は伏せてあり、「利息総額を表示」で表示されます
   （入力を変えて結果が変わると自動で伏せ直します）
5. ツールバーの「支払い表を出力」で、テンプレートと利息の表示有無を選んでPDF保存・印刷・共有
6. 次の患者に移るときは「入力をクリア」

年率欄は起動時に設定の「既定の年率」が入ります。別の値にしたときは注意表示が出ます。
「この値を既定にする」を押したときだけ既定値が更新されます。

入力内容（患者名を含む）は保存されず、アプリを終了すると消えます。

## 設定

Mac はメニューの「設定…」（⌘,）、iPad は右上の歯車から開きます。変更はすぐ保存されます。

- 院名、ロゴ画像、テーマカラー、強調色、フォント、文字サイズ
- 注記文、利息を伏せるときの表示
- 端数処理（切り捨て／切り上げ／四捨五入）、差額の調整（最終回／初回）
- 既定の年率、ボーナス月の初期値
- 使用するテンプレート

保存先: `~/Library/Application Support/InstallmentCalculator/settings.json`
（サンドボックスで実行した場合は `~/Library/Containers/local.clinic.InstallmentCalculator/Data/Library/Application Support/InstallmentCalculator/`）

「設定を書き出す…」で書き出したJSONを別のMacやiPadで「設定を読み込む…」と、ロゴ・既定の年率を含めて同じ設定になります。

## 支払い表テンプレート

テンプレートは設定フォルダ内の `templates/` にあるHTMLファイルです。初回起動時に `default.html` が置かれるので、
それをコピーして編集するのが簡単です。Mac は設定画面の「テンプレートフォルダを開く」、
iPad は「テンプレートを読み込む…」でファイルAppから取り込めます。

### プレースホルダー

金額はカンマ区切りの数字だけが入ります（「円」はテンプレート側で書いてください）。値はHTMLエスケープされます。

| プレースホルダー | 内容 |
|---|---|
| `{{clinic_name}}` | 院名 |
| `{{patient_name}}` | 患者名 |
| `{{issue_date}}` | 作成日（2026年9月30日） |
| `{{principal}}` | 支払総額（元本） |
| `{{annual_rate}}` | 年率（3、2.5 など） |
| `{{installments}}` | 分割回数 |
| `{{monthly_payment}}` | 月額（ボーナスを除く通常回の額） |
| `{{first_payment}}` / `{{last_payment}}` | 初回／最終回の支払額 |
| `{{first_month}}` / `{{last_month}}` | 初回／最終回の支払月 |
| `{{bonus_amount}}` | ボーナス加算額 |
| `{{bonus_months}}` | ボーナス月（6月・12月） |
| `{{total_bonus}}` | ボーナス加算の合計 |
| `{{total_payment}}` | 総支払額 |
| `{{total_interest}}` | 利息総額（「利息を表示する」を選んだときだけ） |
| `{{note}}` | 注記文 |
| `{{theme_color}}` / `{{accent_color}}` | テーマカラー／強調色（#RRGGBB） |
| `{{font_family}}` | 設定のフォント名 |
| `{{logo}}` | ロゴ画像（`<img src="{{logo}}">` で使う data URI） |

### スケジュール表の繰り返し行

`<!-- ROW_START -->` と `<!-- ROW_END -->` で1行分のひな形を囲むと、回数分だけ複製されます。

```html
<!-- ROW_START -->
<tr>
  <td>{{row.no}}</td>
  <td>{{row.month}}</td>
  <td>{{row.payment}}</td>
  <td data-show="bonus">{{row.bonus}}</td>
  <td>{{row.principal}}</td>
  <td data-show="interest">{{row.interest}}</td>
  <td>{{row.balance}}</td>
</tr>
<!-- ROW_END -->
```

### 表示の切り替え（data-show）

`data-show` 属性を付けた要素は、条件に合わないとき要素ごと取り除かれます。

| 属性 | 取り除かれる条件 |
|---|---|
| `data-show="interest"` | 出力時に「利息を表示する」を選ばなかったとき |
| `data-show="bonus"` | ボーナス払いが無いとき |
| `data-show="logo"` | ロゴ画像が設定されていないとき |
| `data-show="patient"` | 患者名が空のとき |

## 未確定事項・注意

- 実際の分割条件は信販会社の計算方法（手数料率表など）と一致しない場合があります。画面と支払い表には必ず「目安」である旨の注記を入れてください（設定の注記文）。
- 別のMacに配布する場合は、署名・公証が必要です（自分のMacだけで使うなら不要）。
- MacとiPadの設定の自動同期（iCloud）は未対応です。設定の書き出し／読み込みで移してください。
