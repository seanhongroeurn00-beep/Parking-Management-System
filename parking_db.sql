-- =====================================================================
-- parking_db : ប្រព័ន្ធគ្រប់គ្រងចំណត (Motor 600, Car 400)
-- Script តែមួយ ស្អាត រត់បានម្តងគត់ (MySQL 8.0.16+)
-- ប្រយ័ត្ន: Script នេះលុបតារាងចាស់ៗ រួចបង្កើតថ្មី (ទិន្នន័យចាស់នឹងបាត់)
-- =====================================================================

CREATE DATABASE IF NOT EXISTS parking_db
    CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE parking_db;
SET NAMES utf8mb4;   -- ឱ្យអក្សរខ្មែរ import ត្រឹមត្រូវលើ Windows

-- ---------------------------------------------------------------------
-- ១. សម្អាតរបស់ចាស់
-- ---------------------------------------------------------------------
DROP VIEW IF EXISTS view_weekly_report;
DROP VIEW IF EXISTS view_monthly_report;
DROP VIEW IF EXISTS view_yearly_report;
DROP VIEW IF EXISTS view_currently_parked;
DROP VIEW IF EXISTS view_frequent_visitors;

DROP TRIGGER IF EXISTS before_vehicle_insert;
DROP TRIGGER IF EXISTS after_vehicle_insert;
DROP TRIGGER IF EXISTS before_vehicle_update;
DROP TRIGGER IF EXISTS after_vehicle_update;
DROP TRIGGER IF EXISTS after_vehicle_delete;
-- trigger ចាស់ៗពីកំណែមុន
DROP TRIGGER IF EXISTS before_vehicle_checkout;
DROP TRIGGER IF EXISTS after_vehicle_entry;
DROP TRIGGER IF EXISTS after_vehicle_exit;

DROP FUNCTION IF EXISTS fn_parking_fee;

DROP TABLE IF EXISTS vehicle_logs;
DROP TABLE IF EXISTS daily_summary;
DROP TABLE IF EXISTS admin_users;
DROP TABLE IF EXISTS parking_capacity;

-- ---------------------------------------------------------------------
-- ២. តារាងសមត្ថភាពចំណត + អត្រាតម្លៃ (កែតម្លៃបានត្រង់នេះ មិនបាច់កែ trigger)
--    Motor: 2,000៛ / 1440 នាទី (១ថ្ងៃ)   Car: 4,000៛ / 60 នាទី (១ម៉ោង)
-- ---------------------------------------------------------------------
CREATE TABLE parking_capacity (
    vehicle_type     VARCHAR(10)   PRIMARY KEY,
    total_capacity   INT           NOT NULL,
    currently_parked INT           NOT NULL DEFAULT 0,
    available_space  INT GENERATED ALWAYS AS (total_capacity - currently_parked) STORED,
    unit_minutes     INT           NOT NULL,          -- រយៈពេលក្នុង ១ ឯកតា (នាទី)
    fee_per_unit     DECIMAL(15,2) NOT NULL,          -- តម្លៃក្នុង ១ ឯកតា (៛)
    CONSTRAINT chk_parked_range CHECK (currently_parked >= 0 AND currently_parked <= total_capacity)
);

INSERT INTO parking_capacity (vehicle_type, total_capacity, unit_minutes, fee_per_unit)
VALUES ('Motor', 600, 1440, 2000.00),
       ('Car',   400,   60, 4000.00);

-- ---------------------------------------------------------------------
-- ៣. តារាងកត់ត្រាចូល-ចេញ
--    total_fee ជា column ធម្មតា (គណនាដោយ trigger) ព្រោះ generated column
--    មិនអាចប្រើជាមួយ FK ... ON UPDATE CASCADE លើ vehicle_type បាន
-- ---------------------------------------------------------------------
CREATE TABLE vehicle_logs (
    id             INT AUTO_INCREMENT PRIMARY KEY,
    plate_no       VARCHAR(20)   NOT NULL,
    vehicle_type   VARCHAR(10)   NOT NULL,
    time_in        DATETIME      NOT NULL,
    time_out       DATETIME      DEFAULT NULL,
    duration_hours DECIMAL(10,2) GENERATED ALWAYS AS (
        IF(time_out IS NOT NULL, ROUND(TIMESTAMPDIFF(MINUTE, time_in, time_out) / 60.0, 2), 0.00)
    ) STORED,
    total_fee      DECIMAL(15,2) NOT NULL DEFAULT 0.00,
    log_date       DATE GENERATED ALWAYS AS (CAST(time_in AS DATE)) STORED,
    -- ការពារស្លាកលេខដូចគ្នា ចូលចតពីរដងដោយមិនទាន់ចេញ
    active_plate   VARCHAR(20) GENERATED ALWAYS AS (IF(time_out IS NULL, plate_no, NULL)) STORED,
    UNIQUE KEY uq_active_plate (active_plate),
    KEY idx_plate (plate_no),
    KEY idx_time_out (time_out),
    CONSTRAINT chk_time_order CHECK (time_out IS NULL OR time_out >= time_in),
    CONSTRAINT fk_logs_type FOREIGN KEY (vehicle_type)
        REFERENCES parking_capacity(vehicle_type) ON UPDATE CASCADE
);

-- ---------------------------------------------------------------------
-- ៤. តារាងរបាយការណ៍ប្រចាំថ្ងៃ (កាលបរិច្ឆេទ = ថ្ងៃចេញ)
-- ---------------------------------------------------------------------
CREATE TABLE daily_summary (
    summary_date         DATE,
    vehicle_type         VARCHAR(10),
    total_vehicles_count INT           NOT NULL DEFAULT 0,
    total_income         DECIMAL(15,2) NOT NULL DEFAULT 0.00,
    PRIMARY KEY (summary_date, vehicle_type)
);

-- ---------------------------------------------------------------------
-- ៥. តារាងអ្នកប្រើប្រាស់ (admin / cashier)
--    password រក្សាទុកជា SHA-256 hash (មិនមែន plain text)
--    កូដកម្មវិធីត្រូវប្រៀបធៀប SHA2(password_ដែលបញ្ចូល, 256)
-- ---------------------------------------------------------------------
CREATE TABLE admin_users (
    id         INT AUTO_INCREMENT PRIMARY KEY,
    username   VARCHAR(50)  NOT NULL UNIQUE,
    password   VARCHAR(255) NOT NULL,
    full_name  VARCHAR(100) NOT NULL,
    role       ENUM('admin','cashier') NOT NULL DEFAULT 'cashier',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO admin_users (username, password, full_name, role) VALUES
('admin',     SHA2('Admin123', 256), 'System Administrator', 'admin'),
('security1', SHA2('Admin123', 256), 'សន្តិសុខ ចាន់ថា',      'cashier');

-- ---------------------------------------------------------------------
-- ៦. Function គណនាតម្លៃ (ប្រើក្នុង trigger)  — យ៉ាងតិច ១ ឯកតា
-- ---------------------------------------------------------------------
DELIMITER $$

CREATE FUNCTION fn_parking_fee(p_type VARCHAR(10), p_in DATETIME, p_out DATETIME)
RETURNS DECIMAL(15,2)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_unit INT;
    DECLARE v_rate DECIMAL(15,2);

    IF p_out IS NULL THEN
        RETURN 0.00;
    END IF;

    SELECT unit_minutes, fee_per_unit INTO v_unit, v_rate
    FROM parking_capacity WHERE vehicle_type = p_type;

    IF v_unit IS NULL THEN
        RETURN 0.00;
    END IF;

    RETURN GREATEST(1, CEIL(TIMESTAMPDIFF(MINUTE, p_in, p_out) / v_unit)) * v_rate;
END$$

-- ---------------------------------------------------------------------
-- ៧. Triggers
-- ---------------------------------------------------------------------

-- ចូល: ពិនិត្យចំណតពេញ + គណនាតម្លៃ (ករណីបញ្ចូលប្រវត្តិមានម៉ោងចេញរួច)
CREATE TRIGGER before_vehicle_insert
BEFORE INSERT ON vehicle_logs
FOR EACH ROW
BEGIN
    DECLARE v_available INT;

    IF NEW.time_out IS NULL THEN
        SELECT available_space INTO v_available
        FROM parking_capacity WHERE vehicle_type = NEW.vehicle_type;

        IF v_available IS NOT NULL AND v_available <= 0 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ចំណតពេញហើយ (Parking is full)';
        END IF;
    END IF;

    SET NEW.total_fee = fn_parking_fee(NEW.vehicle_type, NEW.time_in, NEW.time_out);
END$$

CREATE TRIGGER after_vehicle_insert
AFTER INSERT ON vehicle_logs
FOR EACH ROW
BEGIN
    IF NEW.time_out IS NULL THEN
        -- កំពុងចត
        UPDATE parking_capacity
        SET currently_parked = currently_parked + 1
        WHERE vehicle_type = NEW.vehicle_type;
    ELSE
        -- ប្រវត្តិដែលចេញរួច => បូកចូលរបាយការណ៍
        INSERT INTO daily_summary (summary_date, vehicle_type, total_vehicles_count, total_income)
        VALUES (CAST(NEW.time_out AS DATE), NEW.vehicle_type, 1, NEW.total_fee)
        ON DUPLICATE KEY UPDATE
            total_vehicles_count = total_vehicles_count + 1,
            total_income         = total_income + NEW.total_fee;
    END IF;
END$$

-- កែ/ចេញ: គណនាតម្លៃឡើងវិញ
CREATE TRIGGER before_vehicle_update
BEFORE UPDATE ON vehicle_logs
FOR EACH ROW
BEGIN
    SET NEW.total_fee = fn_parking_fee(NEW.vehicle_type, NEW.time_in, NEW.time_out);
END$$

-- កែ/ចេញ: ធ្វើបច្ចុប្បន្នភាពចំណត + របាយការណ៍
CREATE TRIGGER after_vehicle_update
AFTER UPDATE ON vehicle_logs
FOR EACH ROW
BEGIN
    -- ដកតម្លៃចាស់ចេញពីរបាយការណ៍ (បើធ្លាប់ចេញរួច)
    IF OLD.time_out IS NOT NULL THEN
        UPDATE daily_summary
        SET total_vehicles_count = total_vehicles_count - 1,
            total_income         = total_income - OLD.total_fee
        WHERE summary_date = CAST(OLD.time_out AS DATE)
          AND vehicle_type = OLD.vehicle_type;
    END IF;

    -- បូកតម្លៃថ្មីចូលរបាយការណ៍ (បើចេញរួច)
    IF NEW.time_out IS NOT NULL THEN
        INSERT INTO daily_summary (summary_date, vehicle_type, total_vehicles_count, total_income)
        VALUES (CAST(NEW.time_out AS DATE), NEW.vehicle_type, 1, NEW.total_fee)
        ON DUPLICATE KEY UPDATE
            total_vehicles_count = total_vehicles_count + 1,
            total_income         = total_income + NEW.total_fee;
    END IF;

    -- ចំនួនកំពុងចត
    IF OLD.time_out IS NULL AND NEW.time_out IS NOT NULL THEN
        UPDATE parking_capacity
        SET currently_parked = currently_parked - 1
        WHERE vehicle_type = NEW.vehicle_type;
    ELSEIF OLD.time_out IS NOT NULL AND NEW.time_out IS NULL THEN
        UPDATE parking_capacity
        SET currently_parked = currently_parked + 1
        WHERE vehicle_type = NEW.vehicle_type;
    END IF;
END$$

-- លុប record: កែតម្រូវចំណត/របាយការណ៍ឱ្យត្រូវ
CREATE TRIGGER after_vehicle_delete
AFTER DELETE ON vehicle_logs
FOR EACH ROW
BEGIN
    IF OLD.time_out IS NULL THEN
        UPDATE parking_capacity
        SET currently_parked = currently_parked - 1
        WHERE vehicle_type = OLD.vehicle_type;
    ELSE
        UPDATE daily_summary
        SET total_vehicles_count = total_vehicles_count - 1,
            total_income         = total_income - OLD.total_fee
        WHERE summary_date = CAST(OLD.time_out AS DATE)
          AND vehicle_type = OLD.vehicle_type;
    END IF;
END$$

DELIMITER ;

-- ---------------------------------------------------------------------
-- ៨. Views របាយការណ៍
--    ប្រើ YEARWEEK(...,1) ដើម្បីកុំច្រឡំសប្តាហ៍ចុងឆ្នាំ/ដើមឆ្នាំ
-- ---------------------------------------------------------------------
CREATE VIEW view_weekly_report AS
SELECT YEARWEEK(summary_date, 1) AS year_week,
       FLOOR(YEARWEEK(summary_date, 1) / 100) AS report_year,
       MOD(YEARWEEK(summary_date, 1), 100)    AS report_week,
       MIN(summary_date)         AS week_first_day,
       vehicle_type,
       SUM(total_vehicles_count) AS total_vehicles,
       SUM(total_income)         AS total_income
FROM daily_summary
GROUP BY YEARWEEK(summary_date, 1), vehicle_type;

CREATE VIEW view_monthly_report AS
SELECT YEAR(summary_date)  AS report_year,
       MONTH(summary_date) AS report_month,
       vehicle_type,
       SUM(total_vehicles_count) AS total_vehicles,
       SUM(total_income)         AS total_income
FROM daily_summary
GROUP BY YEAR(summary_date), MONTH(summary_date), vehicle_type;

CREATE VIEW view_yearly_report AS
SELECT YEAR(summary_date) AS report_year,
       vehicle_type,
       SUM(total_vehicles_count) AS total_vehicles,
       SUM(total_income)         AS total_income
FROM daily_summary
GROUP BY YEAR(summary_date), vehicle_type;

-- យានយន្តកំពុងចតឥឡូវនេះ
CREATE VIEW view_currently_parked AS
SELECT id, plate_no, vehicle_type, time_in,
       TIMESTAMPDIFF(MINUTE, time_in, NOW()) AS minutes_parked
FROM vehicle_logs
WHERE time_out IS NULL;

-- អតិថិជនចេញ-ចូលច្រើនដង
CREATE VIEW view_frequent_visitors AS
SELECT plate_no, vehicle_type,
       COUNT(*)            AS total_visits,
       SUM(duration_hours) AS total_hours_parked,
       SUM(total_fee)      AS total_money_spent
FROM vehicle_logs
WHERE time_out IS NOT NULL
GROUP BY plate_no, vehicle_type
HAVING COUNT(*) > 1;

-- ---------------------------------------------------------------------
-- ៩. User MySQL សម្រាប់ Backend (192.168.111.70) — សិទ្ធិតិចបំផុត
--    ប្តូរ password 'Admin@123' មុនប្រើពិតប្រាកដ
-- ---------------------------------------------------------------------
DROP USER IF EXISTS 'parking_app'@'192.168.111.70';
CREATE USER 'parking_app'@'192.168.111.70' IDENTIFIED BY 'Admin@123';
GRANT SELECT, INSERT, UPDATE, DELETE, EXECUTE ON parking_db.* TO 'parking_app'@'192.168.111.70';
FLUSH PRIVILEGES;
 
-- ផ្ទៀងផ្ទាត់
SHOW TABLES;
SHOW TRIGGERS;
SELECT * FROM parking_capacity;
SELECT id, username, full_name, role FROM admin_users;
SHOW GRANTS FOR 'parking_app'@'192.168.111.70';
 