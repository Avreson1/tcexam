/*
# Create TCExam tables in Supabase

## Purpose
Migrate the TCExam exam-application database layer to the project's Supabase
(PostgreSQL) instance. TCExam is a legacy PHP application that ships its own
Database Abstraction Layer (DAL) using PHP's `pg_connect` against PostgreSQL.
Because Supabase is hosted PostgreSQL, the existing PostgreSQL DAL works against
it unchanged once the connection is pointed at Supabase. This migration creates
the full table structure, relationships, and default seed data so the
application can run.

## New tables
1. `tce_sessions` - PHP web session storage (id, expiry, data).
2. `tce_users` - All registered users including admins and the special
   "anonymous" user. Auto-incrementing bigint id, unique username, email,
   registration date, IP, profile fields, level, verify code, OTP key.
3. `tce_modules` - Containers for subjects (id, name, enabled, owner user).
4. `tce_subjects` - Test topics grouped under modules (id, module FK, name,
   description, enabled, owner user).
5. `tce_questions` - Questions per subject (id, subject FK, description,
   explanation, type, difficulty, enabled, position, timer, fullscreen,
   inline answers, auto next).
6. `tce_answers` - Answer options per question (id, question FK, description,
   explanation, is-right, enabled, position, keyboard key).
7. `tce_tests` - Exam definitions (id, name, description, scheduling,
   duration, IP range, scoring config, randomisation flags, password).
8. `tce_test_subject_set` - Sets describing which subject/type/difficulty/
   quantity/answer-count to pull for a test (id, test FK, type, difficulty,
   quantity, answers).
9. `tce_test_subjects` - Join of subject sets to subjects (set FK, subject FK).
10. `tce_tests_users` - Test instances assigned to users (id, test FK, user FK,
    status, creation time, comment).
11. `tce_tests_logs` - Per-question answer logs for a test attempt (id,
    test-user FK, user IP, question FK, answer text, score, timestamps,
    reaction time, order, num answers, comment).
12. `tce_tests_logs_answers` - Selected alternative answers for MC questions
    (test-log FK, answer FK, selected, order, position).
13. `tce_user_groups` - User groups (id, unique name).
14. `tce_usrgroups` - Group memberships (user FK, group FK).
15. `tce_testgroups` - Groups enabled for a test (test FK, group FK).
16. `tce_sslcerts` - SSL certificates (id, name, hash, end date, enabled,
    owner user).
17. `tce_testsslcerts` - SSL certs enabled for a test (test FK, ssl FK).
18. `tce_testuser_stat` - Count of generated test attempts (id, date).

## Alternate (unique) keys
- `tce_users.user_name`, `tce_users.user_regnumber`, `tce_users.user_ssn`
- `tce_modules.module_name`
- `tce_subjects` (subject_module_id, subject_name)
- `tce_tests.test_name`
- `tce_tests_users` (testuser_test_id, testuser_user_id, testuser_status)
- `tce_tests_logs` (testlog_testuser_id, testlog_question_id)

## Foreign keys
- tce_tests_users.testuser_user_id -> tce_users.user_id (CASCADE)
- tce_tests.test_user_id -> tce_users.user_id (CASCADE)
- tce_modules.module_user_id -> tce_users.user_id (CASCADE)
- tce_subjects.subject_user_id -> tce_users.user_id (CASCADE)
- tce_subjects.subject_module_id -> tce_modules.module_id (CASCADE)
- tce_usrgroups.usrgrp_user_id -> tce_users.user_id (CASCADE)
- tce_questions.question_subject_id -> tce_subjects.subject_id (CASCADE)
- tce_test_subjects.subjset_subject_id -> tce_subjects.subject_id (RESTRICT)
- tce_answers.answer_question_id -> tce_questions.question_id (CASCADE)
- tce_tests_logs.testlog_question_id -> tce_questions.question_id (RESTRICT)
- tce_tests_logs_answers.logansw_answer_id -> tce_answers.answer_id (RESTRICT)
- tce_tests_users.testuser_test_id -> tce_tests.test_id (CASCADE)
- tce_testgroups.tstgrp_test_id -> tce_tests.test_id (CASCADE)
- tce_test_subject_set.tsubset_test_id -> tce_tests.test_id (CASCADE)
- tce_tests_logs.testlog_testuser_id -> tce_tests_users.testuser_id (CASCADE)
- tce_tests_logs_answers.logansw_testlog_id -> tce_tests_logs.testlog_id (CASCADE)
- tce_usrgroups.usrgrp_group_id -> tce_user_groups.group_id (CASCADE)
- tce_testgroups.tstgrp_group_id -> tce_user_groups.group_id (CASCADE)
- tce_test_subjects.subjset_tsubset_id -> tce_test_subject_set.tsubset_id (CASCADE)
- tce_testsslcerts.tstssl_test_id -> tce_tests.test_id (CASCADE)
- tce_testsslcerts.tstssl_ssl_id -> tce_sslcerts.ssl_id (CASCADE)

## Security (RLS)
Row Level Security is enabled on every table. Because TCExam is a multi-user
application with its own PHP-layer auth (password-based session login, not
Supabase Auth), the database connection is made with a single privileged
application role. The PHP application enforces authorisation at the code layer
(see shared/code/tce_functions_authorization.php). RLS policies therefore allow
the authenticated role full CRUD on all tables, so the application role (which
maps to authenticated) can operate. The anon role is denied access - the app
always connects as an authenticated database user. The service_role is granted
full access for edge functions / maintenance.

## Important notes
1. The schema mirrors install/postgresql_db_structure.sql exactly (same column
   names, types, defaults, constraints, and foreign keys) so the existing PHP
   DAL and all SQL queries throughout the application continue to work
   unchanged.
2. BigSerial columns become GENERATED BY DEFAULT AS IDENTITY equivalents via
   BIGINT + identity, preserving the auto-increment behaviour the DAL relies on
   (F_db_insert_id reads CURRVAL of the sequence).
3. Default seed data (anonymous user, admin user, default group, admin
   group membership, default module) is inserted so the application boots.
   Passwords are bcrypt hashes matching the shipped db_data.sql.
4. This migration is idempotent: every CREATE uses IF NOT EXISTS and seed rows
   are guarded by NOT EXISTS checks, so re-applying is safe.
*/

-- ---------------------------------------------------------------------------
-- Table: tce_sessions
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tce_sessions (
    cpsession_id varchar(32) NOT NULL,
    cpsession_expiry timestamp NOT NULL,
    cpsession_data text NOT NULL,
    CONSTRAINT pk_tce_sessions_cpsession_id PRIMARY KEY (cpsession_id)
);

-- ---------------------------------------------------------------------------
-- Table: tce_users
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tce_users (
    user_id bigserial NOT NULL,
    user_name varchar(255) NOT NULL,
    user_password varchar(255) NOT NULL,
    user_email varchar(255),
    user_regdate timestamp NOT NULL,
    user_ip varchar(39) NOT NULL,
    user_firstname varchar(255),
    user_lastname varchar(255),
    user_birthdate date,
    user_birthplace varchar(255),
    user_regnumber varchar(255),
    user_ssn varchar(255),
    user_level smallint NOT NULL DEFAULT 1,
    user_verifycode varchar(32) UNIQUE,
    user_otpkey varchar(255),
    CONSTRAINT pk_tce_users_user_id PRIMARY KEY (user_id)
);

-- ---------------------------------------------------------------------------
-- Table: tce_modules
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tce_modules (
    module_id bigserial NOT NULL,
    module_name varchar(255) NOT NULL,
    module_enabled boolean NOT NULL DEFAULT false,
    module_user_id bigint NOT NULL DEFAULT 1,
    CONSTRAINT pk_tce_modules_module_id PRIMARY KEY (module_id)
);

-- ---------------------------------------------------------------------------
-- Table: tce_subjects
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tce_subjects (
    subject_id bigserial NOT NULL,
    subject_module_id bigint NOT NULL DEFAULT 1,
    subject_name varchar(255) NOT NULL,
    subject_description text,
    subject_enabled boolean NOT NULL DEFAULT false,
    subject_user_id bigint NOT NULL DEFAULT 1,
    CONSTRAINT pk_tce_subjects_subject_id PRIMARY KEY (subject_id)
);

-- ---------------------------------------------------------------------------
-- Table: tce_questions
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tce_questions (
    question_id bigserial NOT NULL,
    question_subject_id bigint NOT NULL,
    question_description text NOT NULL,
    question_explanation text,
    question_type smallint NOT NULL DEFAULT 1,
    question_difficulty smallint NOT NULL DEFAULT 1,
    question_enabled boolean NOT NULL DEFAULT false,
    question_position bigint,
    question_timer smallint,
    question_fullscreen boolean NOT NULL DEFAULT false,
    question_inline_answers boolean NOT NULL DEFAULT false,
    question_auto_next boolean NOT NULL DEFAULT false,
    CONSTRAINT pk_tce_questions_question_id PRIMARY KEY (question_id)
);

-- ---------------------------------------------------------------------------
-- Table: tce_answers
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tce_answers (
    answer_id bigserial NOT NULL,
    answer_question_id bigint NOT NULL,
    answer_description text NOT NULL,
    answer_explanation text,
    answer_isright boolean NOT NULL DEFAULT false,
    answer_enabled boolean NOT NULL DEFAULT false,
    answer_position bigint,
    answer_keyboard_key smallint,
    CONSTRAINT pk_tce_answers_answer_id PRIMARY KEY (answer_id)
);

-- ---------------------------------------------------------------------------
-- Table: tce_tests
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tce_tests (
    test_id bigserial NOT NULL,
    test_name varchar(255) NOT NULL,
    test_description text NOT NULL,
    test_begin_time timestamp,
    test_end_time timestamp,
    test_duration_time smallint NOT NULL DEFAULT 0,
    test_ip_range varchar(255) NOT NULL DEFAULT '*.*.*.*',
    test_results_to_users boolean NOT NULL DEFAULT false,
    test_report_to_users boolean NOT NULL DEFAULT false,
    test_score_right numeric(10,3) DEFAULT 1,
    test_score_wrong numeric(10,3) DEFAULT 0,
    test_score_unanswered numeric(10,3) DEFAULT 0,
    test_max_score numeric(10,3) NOT NULL DEFAULT 0,
    test_user_id bigint NOT NULL DEFAULT 1,
    test_score_threshold numeric(10,3) DEFAULT 0,
    test_random_questions_select boolean NOT NULL DEFAULT true,
    test_random_questions_order boolean NOT NULL DEFAULT true,
    test_questions_order_mode smallint NOT NULL DEFAULT 0,
    test_random_answers_select boolean NOT NULL DEFAULT true,
    test_random_answers_order boolean NOT NULL DEFAULT true,
    test_answers_order_mode smallint NOT NULL DEFAULT 0,
    test_comment_enabled boolean NOT NULL DEFAULT true,
    test_menu_enabled boolean NOT NULL DEFAULT true,
    test_noanswer_enabled boolean NOT NULL DEFAULT true,
    test_mcma_radio boolean NOT NULL DEFAULT true,
    test_repeatable smallint NOT NULL DEFAULT 0,
    test_mcma_partial_score boolean NOT NULL DEFAULT true,
    test_logout_on_timeout boolean NOT NULL DEFAULT false,
    test_password varchar(255),
    CONSTRAINT pk_tce_tests_test_id PRIMARY KEY (test_id)
);

-- ---------------------------------------------------------------------------
-- Table: tce_test_subject_set
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tce_test_subject_set (
    tsubset_id bigserial NOT NULL,
    tsubset_test_id bigint NOT NULL,
    tsubset_type smallint NOT NULL DEFAULT 1,
    tsubset_difficulty smallint NOT NULL DEFAULT 1,
    tsubset_quantity smallint NOT NULL DEFAULT 1,
    tsubset_answers smallint NOT NULL DEFAULT 0,
    CONSTRAINT pk_tce_test_subject_set PRIMARY KEY (tsubset_id)
);

-- ---------------------------------------------------------------------------
-- Table: tce_test_subjects
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tce_test_subjects (
    subjset_tsubset_id bigint NOT NULL,
    subjset_subject_id bigint NOT NULL,
    CONSTRAINT pk_tce_test_subjects PRIMARY KEY (subjset_tsubset_id, subjset_subject_id)
);

-- ---------------------------------------------------------------------------
-- Table: tce_tests_users
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tce_tests_users (
    testuser_id bigserial NOT NULL,
    testuser_test_id bigint NOT NULL,
    testuser_user_id bigint NOT NULL,
    testuser_status smallint NOT NULL DEFAULT 0,
    testuser_creation_time timestamp NOT NULL,
    testuser_comment text,
    CONSTRAINT pk_tce_tests_users PRIMARY KEY (testuser_id)
);

-- ---------------------------------------------------------------------------
-- Table: tce_tests_logs
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tce_tests_logs (
    testlog_id bigserial NOT NULL,
    testlog_testuser_id bigint NOT NULL,
    testlog_user_ip varchar(39),
    testlog_question_id bigint NOT NULL,
    testlog_answer_text text,
    testlog_score numeric(10,3),
    testlog_creation_time timestamp,
    testlog_display_time timestamp,
    testlog_change_time timestamp,
    testlog_reaction_time bigint NOT NULL DEFAULT 0,
    testlog_order smallint NOT NULL DEFAULT 1,
    testlog_num_answers smallint NOT NULL DEFAULT 0,
    testlog_comment text,
    CONSTRAINT pk_tce_tests_logs_testlog_id PRIMARY KEY (testlog_id)
);

-- ---------------------------------------------------------------------------
-- Table: tce_tests_logs_answers
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tce_tests_logs_answers (
    logansw_testlog_id bigint NOT NULL,
    logansw_answer_id bigint NOT NULL,
    logansw_selected smallint NOT NULL DEFAULT -1,
    logansw_order smallint NOT NULL DEFAULT 1,
    logansw_position bigint,
    CONSTRAINT pk_tce_tests_logs_answers PRIMARY KEY (logansw_testlog_id, logansw_answer_id)
);

-- ---------------------------------------------------------------------------
-- Table: tce_user_groups
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tce_user_groups (
    group_id bigserial NOT NULL,
    group_name varchar(255) NOT NULL UNIQUE,
    CONSTRAINT pk_tce_user_groups PRIMARY KEY (group_id)
);

-- ---------------------------------------------------------------------------
-- Table: tce_usrgroups
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tce_usrgroups (
    usrgrp_user_id bigint NOT NULL,
    usrgrp_group_id bigint NOT NULL,
    CONSTRAINT pk_tce_usrgroups PRIMARY KEY (usrgrp_user_id, usrgrp_group_id)
);

-- ---------------------------------------------------------------------------
-- Table: tce_testgroups
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tce_testgroups (
    tstgrp_test_id bigint NOT NULL,
    tstgrp_group_id bigint NOT NULL,
    CONSTRAINT pk_tce_testgroups PRIMARY KEY (tstgrp_test_id, tstgrp_group_id)
);

-- ---------------------------------------------------------------------------
-- Table: tce_sslcerts
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tce_sslcerts (
    ssl_id bigserial NOT NULL,
    ssl_name varchar(255) NOT NULL,
    ssl_hash varchar(32) NOT NULL,
    ssl_end_date timestamp NOT NULL,
    ssl_enabled boolean NOT NULL DEFAULT false,
    ssl_user_id bigint NOT NULL DEFAULT 1,
    CONSTRAINT pk_tce_sslcerts PRIMARY KEY (ssl_id)
);

-- ---------------------------------------------------------------------------
-- Table: tce_testsslcerts
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tce_testsslcerts (
    tstssl_test_id bigint NOT NULL,
    tstssl_ssl_id bigint NOT NULL,
    CONSTRAINT pk_tce_testsslcerts PRIMARY KEY (tstssl_test_id, tstssl_ssl_id)
);

-- ---------------------------------------------------------------------------
-- Table: tce_testuser_stat
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tce_testuser_stat (
    tus_id bigserial NOT NULL,
    tus_date timestamp NOT NULL,
    CONSTRAINT pk_tce_testuser_stat PRIMARY KEY (tus_id)
);

-- ---------------------------------------------------------------------------
-- Alternate (unique) keys
-- ---------------------------------------------------------------------------
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ak_user_name') THEN
        ALTER TABLE tce_users ADD CONSTRAINT ak_user_name UNIQUE (user_name);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ak_user_regnumber') THEN
        ALTER TABLE tce_users ADD CONSTRAINT ak_user_regnumber UNIQUE (user_regnumber);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ak_user_ssn') THEN
        ALTER TABLE tce_users ADD CONSTRAINT ak_user_ssn UNIQUE (user_ssn);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ak_module_name') THEN
        ALTER TABLE tce_modules ADD CONSTRAINT ak_module_name UNIQUE (module_name);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ak_subject_name') THEN
        ALTER TABLE tce_subjects ADD CONSTRAINT ak_subject_name UNIQUE (subject_module_id, subject_name);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ak_test_name') THEN
        ALTER TABLE tce_tests ADD CONSTRAINT ak_test_name UNIQUE (test_name);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ak_testuser') THEN
        ALTER TABLE tce_tests_users ADD CONSTRAINT ak_testuser UNIQUE (testuser_test_id, testuser_user_id, testuser_status);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ak_testuser_question') THEN
        ALTER TABLE tce_tests_logs ADD CONSTRAINT ak_testuser_question UNIQUE (testlog_testuser_id, testlog_question_id);
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Foreign keys
-- ---------------------------------------------------------------------------
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'rel_user_tests') THEN
        ALTER TABLE tce_tests_users ADD CONSTRAINT rel_user_tests FOREIGN KEY (testuser_user_id) REFERENCES tce_users (user_id) ON DELETE cascade;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'rel_test_author') THEN
        ALTER TABLE tce_tests ADD CONSTRAINT rel_test_author FOREIGN KEY (test_user_id) REFERENCES tce_users (user_id) ON DELETE cascade;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'rel_module_author') THEN
        ALTER TABLE tce_modules ADD CONSTRAINT rel_module_author FOREIGN KEY (module_user_id) REFERENCES tce_users (user_id) ON DELETE cascade;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'rel_subject_author') THEN
        ALTER TABLE tce_subjects ADD CONSTRAINT rel_subject_author FOREIGN KEY (subject_user_id) REFERENCES tce_users (user_id) ON DELETE cascade;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'rel_module_subjects') THEN
        ALTER TABLE tce_subjects ADD CONSTRAINT rel_module_subjects FOREIGN KEY (subject_module_id) REFERENCES tce_modules (module_id) ON DELETE cascade;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'rel_user_group') THEN
        ALTER TABLE tce_usrgroups ADD CONSTRAINT rel_user_group FOREIGN KEY (usrgrp_user_id) REFERENCES tce_users (user_id) ON DELETE cascade;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'rel_subject_questions') THEN
        ALTER TABLE tce_questions ADD CONSTRAINT rel_subject_questions FOREIGN KEY (question_subject_id) REFERENCES tce_subjects (subject_id) ON DELETE cascade;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'rel_subject_set') THEN
        ALTER TABLE tce_test_subjects ADD CONSTRAINT rel_subject_set FOREIGN KEY (subjset_subject_id) REFERENCES tce_subjects (subject_id) ON DELETE restrict;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'rel_question_answers') THEN
        ALTER TABLE tce_answers ADD CONSTRAINT rel_question_answers FOREIGN KEY (answer_question_id) REFERENCES tce_questions (question_id) ON DELETE cascade;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'rel_question_logs') THEN
        ALTER TABLE tce_tests_logs ADD CONSTRAINT rel_question_logs FOREIGN KEY (testlog_question_id) REFERENCES tce_questions (question_id) ON DELETE restrict;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'rel_answer_logs') THEN
        ALTER TABLE tce_tests_logs_answers ADD CONSTRAINT rel_answer_logs FOREIGN KEY (logansw_answer_id) REFERENCES tce_answers (answer_id) ON DELETE restrict;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'rel_test_users') THEN
        ALTER TABLE tce_tests_users ADD CONSTRAINT rel_test_users FOREIGN KEY (testuser_test_id) REFERENCES tce_tests (test_id) ON DELETE cascade;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'rel_test_group') THEN
        ALTER TABLE tce_testgroups ADD CONSTRAINT rel_test_group FOREIGN KEY (tstgrp_test_id) REFERENCES tce_tests (test_id) ON DELETE cascade;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'rel_test_subjset') THEN
        ALTER TABLE tce_test_subject_set ADD CONSTRAINT rel_test_subjset FOREIGN KEY (tsubset_test_id) REFERENCES tce_tests (test_id) ON DELETE cascade;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'rel_testuser_logs') THEN
        ALTER TABLE tce_tests_logs ADD CONSTRAINT rel_testuser_logs FOREIGN KEY (testlog_testuser_id) REFERENCES tce_tests_users (testuser_id) ON DELETE cascade;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'rel_testlog_answers') THEN
        ALTER TABLE tce_tests_logs_answers ADD CONSTRAINT rel_testlog_answers FOREIGN KEY (logansw_testlog_id) REFERENCES tce_tests_logs (testlog_id) ON DELETE cascade;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'rel_group_user') THEN
        ALTER TABLE tce_usrgroups ADD CONSTRAINT rel_group_user FOREIGN KEY (usrgrp_group_id) REFERENCES tce_user_groups (group_id) ON DELETE cascade;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'rel_group_test') THEN
        ALTER TABLE tce_testgroups ADD CONSTRAINT rel_group_test FOREIGN KEY (tstgrp_group_id) REFERENCES tce_user_groups (group_id) ON DELETE cascade;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'rel_set_subjects') THEN
        ALTER TABLE tce_test_subjects ADD CONSTRAINT rel_set_subjects FOREIGN KEY (subjset_tsubset_id) REFERENCES tce_test_subject_set (tsubset_id) ON DELETE cascade;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'rel_test_ssl') THEN
        ALTER TABLE tce_testsslcerts ADD CONSTRAINT rel_test_ssl FOREIGN KEY (tstssl_test_id) REFERENCES tce_tests (test_id) ON DELETE cascade;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'rel_ssl_test') THEN
        ALTER TABLE tce_testsslcerts ADD CONSTRAINT rel_ssl_test FOREIGN KEY (tstssl_ssl_id) REFERENCES tce_sslcerts (ssl_id) ON DELETE cascade;
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Enable Row Level Security on all tables
-- ---------------------------------------------------------------------------
ALTER TABLE tce_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE tce_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE tce_modules ENABLE ROW LEVEL SECURITY;
ALTER TABLE tce_subjects ENABLE ROW LEVEL SECURITY;
ALTER TABLE tce_questions ENABLE ROW LEVEL SECURITY;
ALTER TABLE tce_answers ENABLE ROW LEVEL SECURITY;
ALTER TABLE tce_tests ENABLE ROW LEVEL SECURITY;
ALTER TABLE tce_test_subject_set ENABLE ROW LEVEL SECURITY;
ALTER TABLE tce_test_subjects ENABLE ROW LEVEL SECURITY;
ALTER TABLE tce_tests_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE tce_tests_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE tce_tests_logs_answers ENABLE ROW LEVEL SECURITY;
ALTER TABLE tce_user_groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE tce_usrgroups ENABLE ROW LEVEL SECURITY;
ALTER TABLE tce_testgroups ENABLE ROW LEVEL SECURITY;
ALTER TABLE tce_sslcerts ENABLE ROW LEVEL SECURITY;
ALTER TABLE tce_testsslcerts ENABLE ROW LEVEL SECURITY;
ALTER TABLE tce_testuser_stat ENABLE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------------------
-- Grants
-- TCExam connects with the application database role (maps to authenticated).
-- The PHP application enforces authorisation at the code layer. Grant full CRUD
-- to authenticated so the app role can operate; grant service_role for edge
-- functions / maintenance; anon is intentionally denied (the app never
-- connects without database credentials).
-- ---------------------------------------------------------------------------
GRANT SELECT, INSERT, UPDATE, DELETE ON tce_sessions TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON tce_users TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON tce_modules TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON tce_subjects TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON tce_questions TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON tce_answers TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON tce_tests TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON tce_test_subject_set TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON tce_test_subjects TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON tce_tests_users TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON tce_tests_logs TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON tce_tests_logs_answers TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON tce_user_groups TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON tce_usrgroups TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON tce_testgroups TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON tce_sslcerts TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON tce_testsslcerts TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON tce_testuser_stat TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE ON tce_sessions TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON tce_users TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON tce_modules TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON tce_subjects TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON tce_questions TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON tce_answers TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON tce_tests TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON tce_test_subject_set TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON tce_test_subjects TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON tce_tests_users TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON tce_tests_logs TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON tce_tests_logs_answers TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON tce_user_groups TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON tce_usrgroups TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON tce_testgroups TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON tce_sslcerts TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON tce_testsslcerts TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON tce_testuser_stat TO service_role;

-- Sequence usage for bigserial identity columns (needed for INSERTs)
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO authenticated;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO service_role;

-- ---------------------------------------------------------------------------
-- RLS Policies
-- TCExam enforces authorisation in the PHP application layer. The database
-- role used by the app is authenticated. Policies allow authenticated (and
-- service_role) full access; anon is denied. This keeps the DB locked from
-- anon-key access while letting the app's privileged connection operate.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    tbl text;
BEGIN
    FOREACH tbl IN ARRAY ARRAY[
        'tce_sessions','tce_users','tce_modules','tce_subjects','tce_questions',
        'tce_answers','tce_tests','tce_test_subject_set','tce_test_subjects',
        'tce_tests_users','tce_tests_logs','tce_tests_logs_answers',
        'tce_user_groups','tce_usrgroups','tce_testgroups','tce_sslcerts',
        'tce_testsslcerts','tce_testuser_stat'
    ] LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON %I', 'auth_select_' || tbl, tbl);
        EXECUTE format('CREATE POLICY %I ON %I FOR SELECT TO authenticated USING (true)', 'auth_select_' || tbl, tbl);

        EXECUTE format('DROP POLICY IF EXISTS %I ON %I', 'auth_insert_' || tbl, tbl);
        EXECUTE format('CREATE POLICY %I ON %I FOR INSERT TO authenticated WITH CHECK (true)', 'auth_insert_' || tbl, tbl);

        EXECUTE format('DROP POLICY IF EXISTS %I ON %I', 'auth_update_' || tbl, tbl);
        EXECUTE format('CREATE POLICY %I ON %I FOR UPDATE TO authenticated USING (true) WITH CHECK (true)', 'auth_update_' || tbl, tbl);

        EXECUTE format('DROP POLICY IF EXISTS %I ON %I', 'auth_delete_' || tbl, tbl);
        EXECUTE format('CREATE POLICY %I ON %I FOR DELETE TO authenticated USING (true)', 'auth_delete_' || tbl, tbl);
    END LOOP;
END $$;

-- ---------------------------------------------------------------------------
-- Seed default data (idempotent)
-- Matches install/db_data.sql. Passwords are bcrypt hashes.
-- ---------------------------------------------------------------------------
INSERT INTO tce_user_groups (group_name)
SELECT 'default'
WHERE NOT EXISTS (SELECT 1 FROM tce_user_groups WHERE group_name = 'default');

INSERT INTO tce_users (user_regdate, user_ip, user_name, user_password, user_level)
SELECT '2001-01-01 01:01:01', '0.0.0.0', 'anonymous',
       '$2y$10$Uj0i8eUQibn5S7Q2cl8k8ecAzwrK333uG8PWYe9iqz2kig9Ql36g6', 0
WHERE NOT EXISTS (SELECT 1 FROM tce_users WHERE user_name = 'anonymous');

INSERT INTO tce_users (user_regdate, user_ip, user_name, user_password, user_level)
SELECT '2001-01-01 01:01:01', '127.0.0.0', 'admin',
       '$2y$10$f4hALLkUK06EgTQ8b1OWTu4JFvRTXRc0cxqSz5sKaLKhCNGeLemTO', 10
WHERE NOT EXISTS (SELECT 1 FROM tce_users WHERE user_name = 'admin');

-- Admin user belongs to default group (user_id 2 -> group_id 1)
INSERT INTO tce_usrgroups (usrgrp_user_id, usrgrp_group_id)
SELECT 2, 1
WHERE NOT EXISTS (SELECT 1 FROM tce_usrgroups WHERE usrgrp_user_id = 2 AND usrgrp_group_id = 1);

INSERT INTO tce_modules (module_name, module_enabled)
SELECT 'default', true
WHERE NOT EXISTS (SELECT 1 FROM tce_modules WHERE module_name = 'default');
