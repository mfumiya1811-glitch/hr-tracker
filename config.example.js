/* ---------------------------------------------------------------------
   このファイルを config.js にコピーして、自分の Supabase の値を入れてください。
   （Supabase ダッシュボード → Project Settings → API で確認できます）

   ここに入れるのは必ず「anon public」キーです。
   service_role キーは絶対にここに書かないでください。
   anon キーは公開前提の設計で、RLS により承認済みデータしか読めません。

   config.js は index.html と同じ階層に置きます。
   設定しない場合、画面上の「接続設定」から入力することもできます
   （その場合は値がブラウザの localStorage にのみ保存されます）。
--------------------------------------------------------------------- */
window.SUPABASE_CONFIG = {
  url: "https://xxxxxxxxxxxx.supabase.co",
  anonKey: "eyJhbGciOi........"
};
