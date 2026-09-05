-- =====================================================================
-- 変更02：データ閲覧をログイン必須にする
--
-- 目的：GitHub Pages で URL を公開しても、ログインしていない人には
--       データが一切見えないようにする。
--
-- 実行方法：Supabase ダッシュボード → SQL Editor に貼り付けて RUN
-- 前提：schema.sql を実行済みであること
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. 未ログイン（anon）向けの閲覧許可を取り消す
-- ---------------------------------------------------------------------
drop policy if exists "公開: 承認済みイベントのみ閲覧可" on hr_events;
drop policy if exists "公開: 企業マスタは閲覧可"        on companies;

-- ---------------------------------------------------------------------
-- 2. ログイン済みユーザーには企業マスタを見せる
--    （hr_events / articles / roster_snapshots / crawl_runs は
--      schema.sql で既に authenticated 向けポリシーを作成済み）
-- ---------------------------------------------------------------------
create policy "レビュー: 企業マスタ閲覧可" on companies
  for select to authenticated using (true);

create policy "レビュー: 企業マスタ更新可" on companies
  for update to authenticated using (true) with check (true);

-- ---------------------------------------------------------------------
-- 3. 確認用：この時点で anon が読めるテーブルは 0 件になっているはず
--    （下を実行すると、どのロールに何が許可されているか一覧できます）
-- ---------------------------------------------------------------------
select
  tablename as テーブル,
  policyname as ポリシー名,
  cmd        as 操作,
  roles      as 対象ロール
from pg_policies
where schemaname = 'public'
order by tablename, policyname;
