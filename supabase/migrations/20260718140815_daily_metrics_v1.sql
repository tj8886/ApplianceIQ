-- ============================================================================
-- DAILY METRICS v1 — closes the coaching loop gap: WS01 Daily Five Scorecard
-- as a live table the AI coach reads from. Ch 90–94 instrument, digitized.
-- ============================================================================
CREATE TABLE IF NOT EXISTS academy_daily_metrics (
  user_id              UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  metric_date          DATE NOT NULL DEFAULT CURRENT_DATE,
  -- The Daily Five (WS01 tallies)
  opportunities        INT NOT NULL DEFAULT 0 CHECK (opportunities >= 0),
  captures             INT NOT NULL DEFAULT 0 CHECK (captures >= 0),
  asks                 INT NOT NULL DEFAULT 0 CHECK (asks >= 0),
  touches              INT NOT NULL DEFAULT 0 CHECK (touches >= 0),
  attach_presentations INT NOT NULL DEFAULT 0 CHECK (attach_presentations >= 0),
  -- Outcomes
  sales                INT NOT NULL DEFAULT 0 CHECK (sales >= 0),
  ticket_total         NUMERIC(12,2) CHECK (ticket_total IS NULL OR ticket_total >= 0),
  -- Daily close (Ch 93)
  debrief              TEXT,
  hot_flags            TEXT,
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, metric_date)
);
CREATE INDEX IF NOT EXISTS idx_adm_user_date ON academy_daily_metrics(user_id, metric_date DESC);

ALTER TABLE academy_daily_metrics ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS p_own_daily_metrics ON academy_daily_metrics;
CREATE POLICY p_own_daily_metrics ON academy_daily_metrics FOR ALL TO authenticated
  USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- Rolling roll-up the portal and coach read (security_invoker: RLS applies)
CREATE OR REPLACE VIEW v_daily_metrics_rollup
WITH (security_invoker = true) AS
SELECT user_id,
  COUNT(*) FILTER (WHERE metric_date >= CURRENT_DATE - 6)                          AS days_logged_7d,
  COALESCE(SUM(opportunities)        FILTER (WHERE metric_date >= CURRENT_DATE - 6),0)  AS opportunities_7d,
  COALESCE(SUM(captures)             FILTER (WHERE metric_date >= CURRENT_DATE - 6),0)  AS captures_7d,
  COALESCE(SUM(asks)                 FILTER (WHERE metric_date >= CURRENT_DATE - 6),0)  AS asks_7d,
  COALESCE(SUM(touches)              FILTER (WHERE metric_date >= CURRENT_DATE - 6),0)  AS touches_7d,
  COALESCE(SUM(attach_presentations) FILTER (WHERE metric_date >= CURRENT_DATE - 6),0)  AS attach_7d,
  COALESCE(SUM(sales)                FILTER (WHERE metric_date >= CURRENT_DATE - 6),0)  AS sales_7d,
  COALESCE(SUM(ticket_total)         FILTER (WHERE metric_date >= CURRENT_DATE - 6),0)  AS ticket_7d,
  COALESCE(SUM(opportunities)        FILTER (WHERE metric_date >= CURRENT_DATE - 27),0) AS opportunities_28d,
  COALESCE(SUM(asks)                 FILTER (WHERE metric_date >= CURRENT_DATE - 27),0) AS asks_28d,
  COALESCE(SUM(sales)                FILTER (WHERE metric_date >= CURRENT_DATE - 27),0) AS sales_28d
FROM academy_daily_metrics
GROUP BY user_id;
