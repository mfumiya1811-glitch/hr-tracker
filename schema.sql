-- =====================================================================
-- 人事異動トラッカー / Supabase スキーマ
-- Supabase ダッシュボードの SQL Editor に貼り付けて実行してください。
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. 企業マスタ（図の A / B / C + URL にあたる部分）
-- ---------------------------------------------------------------------
create table if not exists companies (
  id            bigint generated always as identity primary key,
  name          text not null unique,           -- 例: 第一三共
  name_en       text,
  press_url     text not null,                  -- プレスリリース一覧ページ
  leadership_url text,                          -- 役員一覧ページ（名簿差分用・任意）

  -- 「発見はルール」の中身。company ごとに判定方法が違うため個別に持つ
  url_pattern       text,   -- URL自体に規則がある場合の正規表現。例: '/\d{8}-hr/'
  link_text_pattern text,   -- リンク文言で判定する場合。例: '人事|役員|組織改定'
  content_format    text not null default 'html'
                    check (content_format in ('html','pdf','mixed')),

  -- robots.txt / 規約の確認結果。blocked のものは巡回しない
  access_status text not null default 'unknown'
                check (access_status in ('ok','blocked','paywalled','unknown')),
  access_note   text,

  enabled         boolean not null default true,
  last_crawled_at timestamptz,
  created_at      timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 2. 取得した記事（重複取得を防ぐ台帳）
-- ---------------------------------------------------------------------
create table if not exists articles (
  id           bigint generated always as identity primary key,
  company_id   bigint not null references companies(id) on delete cascade,
  url          text not null unique,            -- 重複排除キー
  title        text,
  published_on date,                            -- 記事の掲載日 = 発表日
  content_hash text,                            -- 本文の差し替え検知用
  is_hr        boolean,                         -- 人事記事と判定したか
  skip_reason  text,                            -- 人事でないと判断した理由
  raw_text     text,                            -- 抽出根拠を後から検証するため保持
  fetched_at   timestamptz not null default now()
);
create index if not exists idx_articles_company on articles(company_id, published_on desc);

-- ---------------------------------------------------------------------
-- 3. 人事異動イベント（本体。既存 index.html の12カラムを踏襲）
-- ---------------------------------------------------------------------
create table if not exists hr_events (
  id          bigint generated always as identity primary key,
  company_id  bigint not null references companies(id) on delete cascade,
  article_id  bigint references articles(id) on delete set null,

  person_name text not null,
  old_title   text,
  old_dept    text,   -- 原文にない場合は必ず NULL のまま（推測で埋めない）
  new_title   text,
  new_dept    text,
  rank        text,   -- 取締役 / 執行役員 / 部長 など
  effective_on date not null,   -- 異動日（原文の「〜付」）
  announced_on date,            -- 発表日（記事の掲載日）
  event_type  text not null
              check (event_type in ('就任','退任','異動','昇格','その他')),

  -- 監査可能性：この行の根拠になった原文をそのまま持つ
  source_url   text,
  source_quote text,
  confidence   text check (confidence in ('high','medium','low')),

  -- レビューキュー
  status      text not null default 'pending'
              check (status in ('pending','approved','rejected')),
  review_note text,
  reviewed_at timestamptz,

  created_at  timestamptz not null default now(),

  -- 同じ記事から同じ人の同じ異動を二重登録しない
  unique (company_id, person_name, effective_on, event_type)
);
create index if not exists idx_hr_status on hr_events(status, effective_on desc);

-- ---------------------------------------------------------------------
-- 4. 役員名簿スナップショット（プレスに出ない異動を差分で拾う）
-- ---------------------------------------------------------------------
create table if not exists roster_snapshots (
  id          bigint generated always as identity primary key,
  company_id  bigint not null references companies(id) on delete cascade,
  captured_at timestamptz not null default now(),
  source_url  text,
  members     jsonb not null   -- [{"職位":"取締役","氏名":"小野 典子","担当":"人財"}, ...]
);

-- ---------------------------------------------------------------------
-- 5. 巡回ログ（どこまで見たか・何が失敗したか）
-- ---------------------------------------------------------------------
create table if not exists crawl_runs (
  id          bigint generated always as identity primary key,
  started_at  timestamptz not null default now(),
  finished_at timestamptz,
  summary     jsonb   -- {"companies":7,"new_articles":3,"new_events":5,"errors":[...]}
);

-- ---------------------------------------------------------------------
-- 6. RLS：公開ページからは「承認済み」だけ読める。書き込みは service_role のみ
-- ---------------------------------------------------------------------
alter table companies       enable row level security;
alter table articles        enable row level security;
alter table hr_events       enable row level security;
alter table roster_snapshots enable row level security;
alter table crawl_runs      enable row level security;

create policy "公開: 企業マスタは閲覧可" on companies
  for select using (true);

create policy "公開: 承認済みイベントのみ閲覧可" on hr_events
  for select using (status = 'approved');

-- articles / roster_snapshots / crawl_runs は anon 向け select ポリシーを作らないため
-- 未ログインでは一切読めません（service_role は RLS を迂回します）。

-- レビュー担当者（Supabase Auth でログイン済み）は pending も含めて全件見え、
-- ステータスを更新できる。承認UIはこの権限で動きます。
create policy "レビュー: 全イベント閲覧可" on hr_events
  for select to authenticated using (true);

create policy "レビュー: ステータス更新可" on hr_events
  for update to authenticated using (true) with check (true);

create policy "レビュー: 原文記事の閲覧可" on articles
  for select to authenticated using (true);

create policy "レビュー: 名簿の閲覧可" on roster_snapshots
  for select to authenticated using (true);

create policy "レビュー: 巡回ログの閲覧可" on crawl_runs
  for select to authenticated using (true);

-- ---------------------------------------------------------------------
-- 7. 初期データ：robots.txt 確認済みの候補企業（2026-09-05 調査）
-- ---------------------------------------------------------------------
insert into companies (name, press_url, leadership_url, url_pattern, link_text_pattern, content_format, access_status, access_note) values
('グラクソ・スミスクライン',
 'https://jp.gsk.com/ja-jp/news/press-releases/',
 'https://jp.gsk.com/ja-jp/company/at-a-glance/',
 '/\d{8}-hr/', null, 'html', 'ok',
 'URLが完全に規則的。役員一覧に執行役員まで掲載あり。検証済み'),

('第一三共',
 'https://www.daiichisankyo.co.jp/media/press_release/',
 'https://www.daiichisankyo.co.jp/about_us/mission-strength/leadership/',
 null, '人事異動|役員人事|組織改定|人事について', 'pdf', 'ok',
 'robots.txt全面許可。人事情報はPDF配信でURLに規則なし。リンク文言で判定する'),

('武田薬品工業',
 'https://www.takeda.com/ja-jp/newsroom/',
 null, null, '人事|役員|組織', 'mixed', 'ok',
 'robots.txt に AnthropicAI: Allow / の明示あり'),

('アステラス製薬',
 'https://www.astellas.com/jp/news',
 null, null, '人事|役員|組織', 'mixed', 'ok',
 'robots.txt はサイトマップ提示のみで実質全面許可'),

('エーザイ',
 'https://www.eisai.co.jp/news/index.html',
 null, null, '人事|役員|組織', 'mixed', 'ok',
 'robots.txt が実質空（全面許可）'),

('中外製薬',
 'https://www.chugai-pharm.co.jp/news/',
 null, null, '人事|役員|組織', 'mixed', 'ok',
 'robots.txt 自体が存在しない（404）＝制限なし'),

('塩野義製薬',
 'https://www.shionogi.com/jp/ja/news.html',
 null, null, '人事|役員|組織', 'mixed', 'ok',
 'robots.txt は画像とdamのみ制限。記事本文は許可')
on conflict (name) do nothing;

-- 参考：規約・robots.txt により対象外と判断したソース
-- ミクスOnline  : robots.txt が ClaudeBot / Claude-User / anthropic-ai を明示Disallow
-- LinkedIn      : robots.txt 冒頭で自動アクセスを明示禁止。加えて個人情報
-- 日刊薬業      : 冒頭のみ無料で以降は会員限定（有料購読者が手動参照する場合のみ）
-- 官報          : 株式会社の役員変更は官報でなく商業登記簿のため情報自体が存在しない
