#!/usr/bin/env bash
# Query the portfolio analytics D1 database with canned reports.
#
# Usage:  ./scripts/stats.sh <report> [--local]
#   daily      visitors + events per day (last 30 days)
#   funnel     distinct sessions per funnel stage (load -> enter -> play)
#   sources    top ?src= tags and referrers
#   companies  visits by network org + city (who is checking you out)
#   returning  visitors who came back (multiple sessions per visitor id)
#   zones      zone popularity (distinct sessions that reached each zone)
#   dialogues  dialogues opened vs completed per zone
#   duration   p50/p90 session length in seconds
#   errors     recent boot errors
#   tech       device / country / perf-tier breakdown
#
# --local queries the local wrangler dev database instead of production.
# Auth: `npx wrangler login` once, or set CLOUDFLARE_API_TOKEN in the env.
set -euo pipefail
cd "$(dirname "$0")/../analytics-worker"

REPORT="${1:-}"
TARGET="--remote"
[[ "${2:-}" == "--local" ]] && TARGET="--local"

case "$REPORT" in
	daily)
		SQL="SELECT date(ts) AS day,
		            COUNT(DISTINCT session_id) AS visitors,
		            COUNT(*) AS events
		     FROM events WHERE name='page_load'
		     GROUP BY day ORDER BY day DESC LIMIT 30;"
		;;
	funnel)
		SQL="SELECT
		       COUNT(DISTINCT CASE WHEN name='page_load'       THEN session_id END) AS loaded,
		       COUNT(DISTINCT CASE WHEN name='boot_ready'      THEN session_id END) AS boot_ready,
		       COUNT(DISTINCT CASE WHEN name='enter_completed' THEN session_id END) AS entered,
		       COUNT(DISTINCT CASE WHEN name='game_started'    THEN session_id END) AS game_started,
		       COUNT(DISTINCT CASE WHEN name='first_move'      THEN session_id END) AS moved
		     FROM events;"
		;;
	sources)
		SQL="SELECT COALESCE(NULLIF(src,''),'(none)') AS src,
		            COALESCE(NULLIF(referrer,''),'(direct)') AS referrer,
		            COUNT(DISTINCT session_id) AS sessions
		     FROM events WHERE name='page_load'
		     GROUP BY src, referrer ORDER BY sessions DESC LIMIT 20;"
		;;
	companies)
		SQL="SELECT COALESCE(NULLIF(org,''),'(unknown)') AS org,
		            COALESCE(NULLIF(city,''),'?') AS city,
		            country,
		            COUNT(DISTINCT session_id) AS sessions,
		            MAX(date(ts)) AS last_seen
		     FROM events WHERE name='page_load'
		     GROUP BY org, city, country ORDER BY sessions DESC, last_seen DESC LIMIT 30;"
		;;
	returning)
		SQL="SELECT substr(visitor_id,1,8) AS visitor,
		            COUNT(DISTINCT session_id) AS visits,
		            date(MIN(ts)) AS first_seen,
		            date(MAX(ts)) AS last_seen,
		            MAX(COALESCE(NULLIF(org,''),'(unknown)')) AS org,
		            MAX(COALESCE(NULLIF(city,''),'?')) AS city,
		            MAX(src) AS src
		     FROM events WHERE name='page_load' AND visitor_id != ''
		     GROUP BY visitor_id HAVING visits > 1
		     ORDER BY visits DESC, last_seen DESC LIMIT 30;"
		;;
	zones)
		SQL="SELECT json_extract(props,'\$.zone') AS zone,
		            COUNT(DISTINCT session_id) AS sessions
		     FROM events WHERE name='zone_visited'
		     GROUP BY zone ORDER BY sessions DESC;"
		;;
	dialogues)
		SQL="SELECT json_extract(props,'\$.zone') AS zone,
		            SUM(name='dialogue_opened') AS opened,
		            SUM(name='dialogue_completed') AS completed
		     FROM events WHERE name IN ('dialogue_opened','dialogue_completed')
		     GROUP BY zone ORDER BY opened DESC;"
		;;
	duration)
		SQL="WITH d AS (
		       SELECT session_id, MAX(CAST(json_extract(props,'\$.t') AS INTEGER)) AS secs
		       FROM events WHERE name='session_ping' GROUP BY session_id
		     ), o AS (
		       SELECT secs, ROW_NUMBER() OVER (ORDER BY secs) AS rn, COUNT(*) OVER () AS n FROM d
		     )
		     SELECT (SELECT secs FROM o WHERE rn=(n+1)/2)         AS p50_secs,
		            (SELECT secs FROM o WHERE rn=MAX(1,(n*9)/10)) AS p90_secs,
		            (SELECT COUNT(*) FROM d)                      AS sessions
		     FROM o LIMIT 1;"
		;;
	errors)
		SQL="SELECT ts, json_extract(props,'\$.msg') AS msg,
		            json_extract(props,'\$.fatal') AS fatal, device, country
		     FROM events WHERE name='boot_error'
		     ORDER BY ts DESC LIMIT 20;"
		;;
	tech)
		SQL="SELECT device, country,
		            COALESCE(json_extract(props,'\$.tier'),'(n/a)') AS tier,
		            COUNT(DISTINCT session_id) AS sessions
		     FROM events WHERE name IN ('page_load','game_started')
		     GROUP BY device, country, tier ORDER BY sessions DESC LIMIT 30;"
		;;
	*)
		sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
		exit 1
		;;
esac

exec npx wrangler d1 execute portfolio_analytics "$TARGET" --command "$SQL"
