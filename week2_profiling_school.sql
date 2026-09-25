-- =====================================================================
--  WEEK 2 - PROFILING QUERY PACK
--  Domain: School
--  Schema: raw_school
--
--  Your question this term:
--    Which subjects show the weakest results, and how does attendance relate to score across terms?
--
--  HOW TO USE THIS FILE
--  Work through it top to bottom. Run each query, look at the result,
--  and write down what you find. By the end you should be able to
--  answer: what is in this data, and what is wrong with it?
--
--  Do not skip to the interesting queries at the bottom. The whole
--  point of week 2 is finding the problems BEFORE you build on them.
--
--  Write your findings in a file called data_quality_notes.md and
--  commit it. Week 3 depends on it.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. WHAT IS HERE?
--    Always start by finding out what tables you have and how big.
-- ---------------------------------------------------------------------

SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'raw_school'
ORDER BY table_name;

-- Row counts, one per table.
SELECT 'results' AS table_name, count(*) AS rows FROM raw_school.results
UNION ALL
SELECT 'students' AS table_name, count(*) AS rows FROM raw_school.students
UNION ALL
SELECT 'subjects' AS table_name, count(*) AS rows FROM raw_school.subjects
UNION ALL
SELECT 'teachers' AS table_name, count(*) AS rows FROM raw_school.teachers
ORDER BY table_name;


-- ---------------------------------------------------------------------
-- 2. LOOK AT THE DATA
--    Never analyse a table you have not actually looked at.
-- ---------------------------------------------------------------------

SELECT * FROM raw_school.results LIMIT 20;
SELECT * FROM raw_school.students LIMIT 10;
SELECT * FROM raw_school.subjects LIMIT 10;
SELECT * FROM raw_school.teachers LIMIT 10;

-- Column names and declared types.
SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'raw_school'
ORDER BY table_name, ordinal_position;

-- NOTE: the date columns are stored as TEXT, not DATE. That is not a
-- mistake in the setup - the source data has mixed formats and would
-- not load as dates. Converting them is your job in week 3.


-- ---------------------------------------------------------------------
-- 3. MISSING VALUES
--    Which columns have gaps, and how big are they?
-- ---------------------------------------------------------------------

SELECT
    count(*)                                        AS total_rows,
    count(*) FILTER (WHERE exam_date IS NULL)             AS missing_exam_date,
    count(*) FILTER (WHERE term IS NULL)                  AS missing_term,
    count(*) FILTER (WHERE score IS NULL)                 AS missing_score,
    count(*) FILTER (WHERE student_id IS NULL)            AS missing_student_id,
    count(*) FILTER (WHERE subject_id IS NULL)            AS missing_subject_id,
    count(*) FILTER (WHERE teacher_id IS NULL)            AS missing_teacher_id
FROM raw_school.results;

-- Ask yourself: is a NULL here a data-entry failure, or does it mean
-- something real? The answer changes how you handle it.


-- ---------------------------------------------------------------------
-- 4. DUPLICATES
--    Exact duplicate rows are usually a loading or export error.
-- ---------------------------------------------------------------------

-- Is the primary key actually unique?
SELECT count(*) AS total_rows,
       count(DISTINCT result_id) AS distinct_ids,
       count(*) - count(DISTINCT result_id) AS extra_rows
FROM raw_school.results;

-- Show the offending rows so you can see what they look like.
SELECT result_id, count(*) AS times_repeated
FROM raw_school.results
GROUP BY result_id
HAVING count(*) > 1
ORDER BY times_repeated DESC, result_id
LIMIT 20;


-- ---------------------------------------------------------------------
-- 5. INCONSISTENT CATEGORIES
--    The same value written several different ways will split your
--    totals in Power BI. This is the classic silent error.
-- ---------------------------------------------------------------------

SELECT term, count(*) AS rows
FROM raw_school.results
GROUP BY term
ORDER BY term;

-- Now compare with the cleaned-up version. How many real categories
-- are there actually?
SELECT upper(trim(term)) AS cleaned, count(*) AS rows
FROM raw_school.results
GROUP BY cleaned
ORDER BY rows DESC;

-- Check the other text columns the same way before you assume they
-- are fine.


-- ---------------------------------------------------------------------
-- 6. DATE FORMATS
--    The date column is text and does not use one format.
-- ---------------------------------------------------------------------

-- Group by shape to see which formats are present.
SELECT
    CASE
        WHEN exam_date ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN 'YYYY-MM-DD'
        WHEN exam_date ~ '^[0-9]{2}/[0-9]{2}/[0-9]{4}$' THEN 'DD/MM/YYYY'
        WHEN exam_date ~ '^[0-9]{4}/[0-9]{2}/[0-9]{2}$' THEN 'YYYY/MM/DD'
        WHEN exam_date ~ '^[0-9]{2}-[A-Za-z]{3}-[0-9]{4}$' THEN 'DD-Mon-YYYY'
        ELSE 'OTHER - investigate'
    END AS date_format,
    count(*) AS rows
FROM raw_school.results
GROUP BY date_format
ORDER BY rows DESC;

-- Careful: 03/04/2025 is ambiguous. Is it 3 April or 4 March?
-- Decide, write your decision down, and apply it consistently.


-- ---------------------------------------------------------------------
-- 7. IMPOSSIBLE VALUES
--    Values that are technically valid numbers but cannot be real.
-- ---------------------------------------------------------------------

SELECT count(*) AS scores_above_the_maximum
FROM raw_school.results
WHERE score > 100;

SELECT *
FROM raw_school.results
WHERE score > 100
LIMIT 15;

-- Also check the range of every numeric column. Anything at the
-- extremes worth questioning?
SELECT
    min(score) AS min_score,
    max(score) AS max_score,
    round(avg(score), 2) AS avg_score
FROM raw_school.results;


-- ---------------------------------------------------------------------
-- 8. BROKEN RELATIONSHIPS
--    Fact rows pointing at dimension records that do not exist.
--    These will silently disappear from your Power BI model.
-- ---------------------------------------------------------------------

-- student_id without a matching row in students
SELECT count(*) AS orphan_student_id
FROM raw_school.results f
LEFT JOIN raw_school.students d ON f.student_id = d.student_id
WHERE d.student_id IS NULL;

-- subject_id without a matching row in subjects
SELECT count(*) AS orphan_subject_id
FROM raw_school.results f
LEFT JOIN raw_school.subjects d ON f.subject_id = d.subject_id
WHERE d.subject_id IS NULL;

-- teacher_id without a matching row in teachers
SELECT count(*) AS orphan_teacher_id
FROM raw_school.results f
LEFT JOIN raw_school.teachers d ON f.teacher_id = d.teacher_id
WHERE d.teacher_id IS NULL;

-- If you find orphans: do you drop those rows, or keep them with an
-- "Unknown" placeholder? Both are defensible. Document which you chose.


-- ---------------------------------------------------------------------
-- 9. TIME COVERAGE
--    Does the data actually cover the period you think it does?
-- ---------------------------------------------------------------------

SELECT
    min(exam_date) AS earliest_text,
    max(exam_date) AS latest_text
FROM raw_school.results;

-- That result is misleading, because text sorts alphabetically, not
-- chronologically. Work out why, then check the real range once you
-- have parsed the dates in week 3. This is a good thing to note down.


-- ---------------------------------------------------------------------
-- 10. YOUR FIRST REAL ANALYSIS
--     Only meaningful once you know what is broken above.
-- ---------------------------------------------------------------------

-- Volume and value by subject_name.
SELECT
    d.subject_name,
    count(*)                       AS rows,
    round(sum(f.score), 2)      AS total_score,
    round(avg(f.score), 2)      AS avg_score
FROM raw_school.results f
JOIN raw_school.subjects d ON f.subject_id = d.subject_id
GROUP BY d.subject_name
ORDER BY total_score DESC;

-- The same thing by month. substring() is a temporary shortcut that
-- only works for the rows already in YYYY-MM-DD form - which is
-- exactly why week 3 exists.
SELECT
    substring(exam_date FROM 1 FOR 7) AS month,
    count(*)                           AS rows,
    round(sum(score), 2)            AS total_score
FROM raw_school.results
WHERE exam_date ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
GROUP BY month
ORDER BY month;

-- How many rows did that WHERE clause silently throw away?
-- Check. Then think about what that would have done to a dashboard.


-- ---------------------------------------------------------------------
-- 11. THE FULL JOIN
--     Everything connected. This is roughly the shape your fact table
--     will take in week 4.
-- ---------------------------------------------------------------------

SELECT
    f.result_id,
    f.exam_date,
    f.score,
    students.*,
    subjects.*,
    teachers.*
FROM raw_school.results f
JOIN raw_school.students AS students ON f.student_id = students.student_id
JOIN raw_school.subjects AS subjects ON f.subject_id = subjects.subject_id
JOIN raw_school.teachers AS teachers ON f.teacher_id = teachers.teacher_id
LIMIT 25;


-- =====================================================================
--  BEFORE YOU FINISH WEEK 2
--
--  Your data_quality_notes.md should answer:
--    1. How many rows in each table?
--    2. Which columns have missing values, and how many?
--    3. How many duplicate rows, and in which table?
--    4. How many real categories are hiding behind the messy ones?
--    5. Which date formats are present?
--    6. How many impossible values, and what will you do about them?
--    7. How many orphan keys, and what will you do about them?
--
--  Commit it. Week 3 starts from this file, not from memory.
-- =====================================================================
