-- Analysis queries for the AWS Job Market Tracker.
-- Run in the Athena query editor after setup.sql.


-- How much data do we have? Postings per day and role.
SELECT dt, search_term, COUNT(*) AS postings
FROM jobtracker.postings
GROUP BY dt, search_term
ORDER BY dt, search_term;


-- Top skills per role: share of unique postings that mention each skill.
WITH totals AS (
  SELECT search_term, COUNT(*) AS total
  FROM jobtracker.postings_unique
  GROUP BY search_term
)
SELECT p.search_term,
       s.skill,
       COUNT(*)                                AS postings,
       ROUND(100.0 * COUNT(*) / t.total, 1)    AS pct
FROM jobtracker.postings_unique p
CROSS JOIN UNNEST(p.skills) AS s(skill)
JOIN totals t ON p.search_term = t.search_term
GROUP BY p.search_term, s.skill, t.total
ORDER BY p.search_term, pct DESC;


-- AWS vs. Azure vs. GCP in cloud engineer postings.
SELECT
  ROUND(100.0 * COUNT_IF(contains(skills, 'AWS'))   / COUNT(*), 1) AS aws_pct,
  ROUND(100.0 * COUNT_IF(contains(skills, 'Azure')) / COUNT(*), 1) AS azure_pct,
  ROUND(100.0 * COUNT_IF(contains(skills, 'GCP'))   / COUNT(*), 1) AS gcp_pct,
  COUNT(*)                                                         AS postings
FROM jobtracker.postings_unique
WHERE search_term = 'cloud engineer';


-- Trend over time: share of each day's new cloud postings mentioning a skill.
SELECT dt,
       COUNT(*)                                                             AS new_postings,
       ROUND(100.0 * COUNT_IF(contains(skills, 'AWS'))       / COUNT(*), 1) AS aws_pct,
       ROUND(100.0 * COUNT_IF(contains(skills, 'Azure'))     / COUNT(*), 1) AS azure_pct,
       ROUND(100.0 * COUNT_IF(contains(skills, 'Terraform')) / COUNT(*), 1) AS terraform_pct
FROM jobtracker.postings_unique
WHERE search_term = 'cloud engineer'
GROUP BY dt
ORDER BY dt;


-- Median stated salary by role (employer-stated salaries only).
SELECT search_term,
       COUNT(*)                                                AS postings_with_salary,
       ROUND(approx_percentile((salary_min + salary_max) / 2, 0.5)) AS median_salary
FROM jobtracker.postings_unique
WHERE salary_is_predicted = false
  AND salary_min IS NOT NULL
  AND salary_max IS NOT NULL
GROUP BY search_term;


-- States with the most postings per role.
SELECT search_term, state, COUNT(*) AS postings
FROM jobtracker.postings_unique
WHERE state IS NOT NULL
GROUP BY search_term, state
ORDER BY search_term, postings DESC;


-- Companies hiring the most cloud engineers.
SELECT company, COUNT(*) AS postings
FROM jobtracker.postings_unique
WHERE search_term = 'cloud engineer' AND company IS NOT NULL
GROUP BY company
ORDER BY postings DESC
LIMIT 15;