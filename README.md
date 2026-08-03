# TeXNote

カード単位で本文、preamble、TeXエンジンを保持するmacOS用TeXノートです。
1つのTeXNoteを通常のフォルダとして保存します。

## 必要環境

- macOS 15以降
- Xcode 26以降
- MacTeX（既定の探索先は `/Library/TeX/texbin`）

## 起動

`TeXNote.xcodeproj` をXcodeで開き、`TeXNote` schemeを実行します。

カードに入力するのは `\begin{document}` と `\end{document}` の内側だけです。
完全なTeXソースは組版時にカード固有の設定から生成されます。

「保存」では選択した場所にノート名と同名のフォルダを作成します。
「開く」では `note.json` を含むNoteフォルダを選択します。

保存されたパッケージの内部構成は次のとおりです。

```text
ノート名/
├── note.json        # Portableな正本
└── PDF/
    └── カードUUID.pdf
```

検索索引はGRDB経由のSQLiteとしてApplication Support内に保存されます。
索引DBはNoteフォルダに含めず、`note.json`から再構築できます。

メイン画面はカード一覧と、選択カードのPDFページ横スクロールで構成されます。
「編集」からTeXソース、設定、エラーの各タブを開き、「保存・版組」で更新します。

## プラットフォーム展開

Xcodeには次の2つのschemeがあります。

- `TeXNote`: macOS版
- `TeXNote iPad`: iPadOS版

モデル、GRDB、Noteフォルダ、検索、カード編集、PDF表示は同じ共有実装です。
iPad固有のルート画面とInfo設定だけを `Platform/iPad` に置いています。

`TeXCompilerFactory`も1つだけで、macOSでは`LocalTeXCompiler`を返します。
iPadOSでは将来のリモート版組実装を差し込む構造で、現時点では編集内容の保存後に
「版組サーバーはまだ設定されていません」とエラータブへ表示します。
