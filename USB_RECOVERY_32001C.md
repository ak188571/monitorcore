# Tang Console 138K: 日本語一覧のUSB Host回復

基板表示「32001C」の日本語一覧用monitor。P1/P2に同じUSB Host自動回復を適用する。最初のHID report後、`START`待ちが100 ms続くか`conerr`が立ったとき、Host全体を約5 ms resetする。新しいreportが届くまで自動resetを繰り返さない。S1（USER_BUTTON0、AA13）を押している間は両Hostを手動resetし、PMODの8個のLEDを全点灯する。

PMODのLED0〜7は順に、P1の新button（約0.5秒）、P1 `connected`、P1の直近report（約0.5秒）、P1自動reset履歴、P2の新button、P2 `connected`、P2の直近report、P2自動reset履歴。履歴はS1または電源resetで消える。

VID:PID `0079:0006`で日本語一覧のP1/P2をそれぞれ約25回挿抜し、毎回操作できた。両portで自動reset履歴が点灯した。S1を押している間の全LED点灯も確認した。抜去直後に一時的な誤入力があったが、再接続後は通常の操作に戻ったため、今回は修正しない。

Gowin V1.9.12.03、`GW5AST-LV138PG484AC1/I0` version B、`gw_sh build.tcl console138k`。設計全体のLogic 2,761/138,240、Register 1,971/139,095。setup 63、hold 4 endpointの違反が残る。採択した`cores/console138k/monitor.bin`は4,450,196 byte、SHA-256 `B8E1914B4F389C1913A593E5E47C03445471CB748C48C644688B7E2C09F34F3D`。元版と実機試験の詳細は作業領域の総合報告に記録した。

このbranchでは、元のHEADにない日本語UI16 sourceの前提変更と、USB回復の変更を分けてcommitする。前提変更を省くと実機で試したBitstreamのsourceにならない。ゲームROMとBL616 Flashは変更しない。
