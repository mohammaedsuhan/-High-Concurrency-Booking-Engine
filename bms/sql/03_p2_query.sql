USE bms;

-- P2 (a): flat list. One row per show, ordered by movie then time.
-- Parameters: theatre_id and show_date.
SELECT  m.title                      AS movie,
        l.name                       AS language,
        f.name                       AS format,
        s.name                       AS screen,
        sh.show_id,
        TIME_FORMAT(sh.start_time, '%h:%i %p') AS show_time
FROM    `show` sh
JOIN    screen  s ON s.screen_id   = sh.screen_id
JOIN    movie   m ON m.movie_id    = sh.movie_id
JOIN    language l ON l.language_id = sh.language_id
JOIN    format  f ON f.format_id   = sh.format_id
WHERE   s.theatre_id = 1              -- <- given theatre
  AND   sh.show_date = CURDATE()      -- <- given date, e.g. '2026-10-01'
  AND   sh.status    = 'SCHEDULED'
ORDER BY m.title, l.name, f.name, sh.start_time;

-- P2 (b): grouped like the reference UI: one row per movie/language/format with all timings.
SELECT  m.title  AS movie,
        l.name   AS language,
        f.name   AS format,
        GROUP_CONCAT(TIME_FORMAT(sh.start_time,'%h:%i %p') ORDER BY sh.start_time SEPARATOR ' | ') AS show_timings
FROM    `show` sh
JOIN    screen  s ON s.screen_id   = sh.screen_id
JOIN    movie   m ON m.movie_id    = sh.movie_id
JOIN    language l ON l.language_id = sh.language_id
JOIN    format  f ON f.format_id   = sh.format_id
WHERE   s.theatre_id = 1
  AND   sh.show_date = CURDATE()
  AND   sh.status    = 'SCHEDULED'
GROUP BY m.movie_id, m.title, l.language_id, l.name, f.format_id, f.name
ORDER BY m.title;

-- Bonus: the 7-day date strip (today + next 6 days) for the date picker.
WITH RECURSIVE d (n) AS (SELECT 0 UNION ALL SELECT n+1 FROM d WHERE n < 6)
SELECT CURDATE() + INTERVAL n DAY AS show_date,
       DATE_FORMAT(CURDATE() + INTERVAL n DAY, '%a %d %b') AS label
FROM d;
