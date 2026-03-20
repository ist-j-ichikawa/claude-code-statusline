# TODO

## Go/Rust でのリライト検討

bashの本質的制約としてJSON解析・ファイルstat等が全てfork（プロセス生成）になり、
高負荷時にClaude Codeのstatuslineタイムアウトに引っかかることがある。

コンパイル言語なら全操作がプロセス内で完結するため根本解決になる。

- Claude Codeのstatuslineは shebang/バイナリ問わず「stdin JSON → stdout行出力 → exit 0」を満たせばOK
- 現状 bash で 50-60ms → Go なら ~5ms、Rust なら ~2ms が目安
- git操作は `go-git` や `git2-go`/`libgit2` でプロセス内実行可能
- JSON解析も標準ライブラリで fork 不要
- キャッシュ機構（git 5s, subscription 3600s）は同じ設計で移植可能
