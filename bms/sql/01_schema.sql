-- BookMyShow-style ticketing schema (MySQL 8.0+, InnoDB, utf8mb4)
CREATE DATABASE IF NOT EXISTS bms CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE bms;

CREATE TABLE city (
  city_id   INT UNSIGNED NOT NULL AUTO_INCREMENT,
  name      VARCHAR(80)  NOT NULL,
  state     VARCHAR(80)  NOT NULL,
  PRIMARY KEY (city_id),
  UNIQUE KEY uq_city (name, state)
) ENGINE=InnoDB;

CREATE TABLE theatre (
  theatre_id INT UNSIGNED NOT NULL AUTO_INCREMENT,
  city_id    INT UNSIGNED NOT NULL,
  name       VARCHAR(150) NOT NULL,
  address    VARCHAR(255) NOT NULL,
  PRIMARY KEY (theatre_id),
  UNIQUE KEY uq_theatre (city_id, name),
  CONSTRAINT fk_theatre_city FOREIGN KEY (city_id) REFERENCES city(city_id)
) ENGINE=InnoDB;

CREATE TABLE screen (
  screen_id  INT UNSIGNED NOT NULL AUTO_INCREMENT,
  theatre_id INT UNSIGNED NOT NULL,
  name       VARCHAR(50)  NOT NULL,            -- 'Audi 1', 'Screen 2'
  PRIMARY KEY (screen_id),
  UNIQUE KEY uq_screen (theatre_id, name),     -- also serves the theatre->screens lookup
  CONSTRAINT fk_screen_theatre FOREIGN KEY (theatre_id) REFERENCES theatre(theatre_id)
) ENGINE=InnoDB;

CREATE TABLE seat_category (
  category_id INT UNSIGNED NOT NULL AUTO_INCREMENT,
  name        VARCHAR(40)  NOT NULL,           -- 'Classic', 'Prime', 'Recliner'
  PRIMARY KEY (category_id),
  UNIQUE KEY uq_seat_category (name)
) ENGINE=InnoDB;

CREATE TABLE seat (                            -- physical seat, created once per screen
  seat_id     INT UNSIGNED NOT NULL AUTO_INCREMENT,
  screen_id   INT UNSIGNED NOT NULL,
  row_label   CHAR(2)      NOT NULL,           -- 'A', 'B', ... 'AA'
  seat_number SMALLINT UNSIGNED NOT NULL,
  category_id INT UNSIGNED NOT NULL,
  PRIMARY KEY (seat_id),
  UNIQUE KEY uq_seat_position (screen_id, row_label, seat_number),
  CONSTRAINT fk_seat_screen   FOREIGN KEY (screen_id)   REFERENCES screen(screen_id),
  CONSTRAINT fk_seat_category FOREIGN KEY (category_id) REFERENCES seat_category(category_id)
) ENGINE=InnoDB;

CREATE TABLE language (
  language_id INT UNSIGNED NOT NULL AUTO_INCREMENT,
  name        VARCHAR(40)  NOT NULL,
  PRIMARY KEY (language_id),
  UNIQUE KEY uq_language (name)
) ENGINE=InnoDB;

CREATE TABLE format (                          -- screening format: '2D', '3D', 'IMAX 2D'
  format_id INT UNSIGNED NOT NULL AUTO_INCREMENT,
  name      VARCHAR(40)  NOT NULL,
  PRIMARY KEY (format_id),
  UNIQUE KEY uq_format (name)
) ENGINE=InnoDB;

CREATE TABLE movie (
  movie_id     INT UNSIGNED NOT NULL AUTO_INCREMENT,
  title        VARCHAR(200) NOT NULL,
  duration_min SMALLINT UNSIGNED NOT NULL,
  certificate  ENUM('U','UA','A','S') NOT NULL,
  release_date DATE NOT NULL,
  PRIMARY KEY (movie_id),
  UNIQUE KEY uq_movie (title, release_date)
) ENGINE=InnoDB;

CREATE TABLE `show` (                          -- one screening of a movie on a screen
  show_id     BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  screen_id   INT UNSIGNED NOT NULL,
  movie_id    INT UNSIGNED NOT NULL,
  language_id INT UNSIGNED NOT NULL,
  format_id   INT UNSIGNED NOT NULL,
  show_date   DATE NOT NULL,
  start_time  TIME NOT NULL,
  end_time    TIME NOT NULL,                   -- assumes a show does not cross midnight (see doc)
  status      ENUM('SCHEDULED','CANCELLED') NOT NULL DEFAULT 'SCHEDULED',
  PRIMARY KEY (show_id),
  -- A screen can run only one show at a given start time; also the P2 access path.
  UNIQUE KEY uq_show_slot (screen_id, show_date, start_time),
  KEY idx_show_movie_date (movie_id, show_date),
  CONSTRAINT chk_show_time CHECK (end_time > start_time),
  CONSTRAINT fk_show_screen   FOREIGN KEY (screen_id)   REFERENCES screen(screen_id),
  CONSTRAINT fk_show_movie    FOREIGN KEY (movie_id)    REFERENCES movie(movie_id),
  CONSTRAINT fk_show_language FOREIGN KEY (language_id) REFERENCES language(language_id),
  CONSTRAINT fk_show_format   FOREIGN KEY (format_id)   REFERENCES format(format_id)
) ENGINE=InnoDB;

CREATE TABLE show_price (                      -- price depends on (show, seat category)
  show_id     BIGINT UNSIGNED NOT NULL,
  category_id INT UNSIGNED NOT NULL,
  price       DECIMAL(8,2) NOT NULL,
  PRIMARY KEY (show_id, category_id),
  CONSTRAINT chk_price CHECK (price >= 0),
  CONSTRAINT fk_sp_show     FOREIGN KEY (show_id)     REFERENCES `show`(show_id),
  CONSTRAINT fk_sp_category FOREIGN KEY (category_id) REFERENCES seat_category(category_id)
) ENGINE=InnoDB;

CREATE TABLE app_user (
  user_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  name    VARCHAR(120) NOT NULL,
  email   VARCHAR(190) NOT NULL,
  phone   VARCHAR(20)  NOT NULL,
  PRIMARY KEY (user_id),
  UNIQUE KEY uq_user_email (email),
  UNIQUE KEY uq_user_phone (phone)
) ENGINE=InnoDB;

CREATE TABLE booking (
  booking_id      BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id         BIGINT UNSIGNED NOT NULL,
  show_id         BIGINT UNSIGNED NOT NULL,
  status          ENUM('PENDING','CONFIRMED','EXPIRED','CANCELLED') NOT NULL DEFAULT 'PENDING',
  total_amount    DECIMAL(10,2) NOT NULL,      -- price snapshot at hold time (prices may change later)
  hold_expires_at DATETIME NOT NULL,
  created_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (booking_id),
  KEY idx_booking_user (user_id, created_at),
  KEY idx_booking_expiry (status, hold_expires_at),   -- sweeper job
  CONSTRAINT fk_booking_user FOREIGN KEY (user_id) REFERENCES app_user(user_id),
  CONSTRAINT fk_booking_show FOREIGN KEY (show_id) REFERENCES `show`(show_id)
) ENGINE=InnoDB;

-- The concurrency hot-spot: one row per (show, seat), pre-generated when a show is scheduled.
CREATE TABLE show_seat (
  show_seat_id    BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  show_id         BIGINT UNSIGNED NOT NULL,
  seat_id         INT UNSIGNED NOT NULL,
  status          ENUM('AVAILABLE','HELD','BOOKED') NOT NULL DEFAULT 'AVAILABLE',
  booking_id      BIGINT UNSIGNED NULL,        -- owner while HELD / BOOKED
  hold_expires_at DATETIME NULL,               -- set only while HELD
  version         INT UNSIGNED NOT NULL DEFAULT 0,   -- optimistic-lock counter
  PRIMARY KEY (show_seat_id),
  UNIQUE KEY uq_show_seat (show_id, seat_id),  -- DB-level guarantee: a seat exists once per show
  KEY idx_show_seat_booking (booking_id),
  KEY idx_show_seat_expiry (status, hold_expires_at),
  CONSTRAINT chk_show_seat_state CHECK (
       (status = 'AVAILABLE' AND booking_id IS NULL AND hold_expires_at IS NULL)
    OR (status = 'HELD'      AND booking_id IS NOT NULL AND hold_expires_at IS NOT NULL)
    OR (status = 'BOOKED'    AND booking_id IS NOT NULL AND hold_expires_at IS NULL)),
  CONSTRAINT fk_ss_show    FOREIGN KEY (show_id)    REFERENCES `show`(show_id),
  CONSTRAINT fk_ss_seat    FOREIGN KEY (seat_id)    REFERENCES seat(seat_id),
  CONSTRAINT fk_ss_booking FOREIGN KEY (booking_id) REFERENCES booking(booking_id)
) ENGINE=InnoDB;

CREATE TABLE payment (
  payment_id     BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  booking_id     BIGINT UNSIGNED NOT NULL,
  gateway        VARCHAR(30) NOT NULL,
  gateway_txn_id VARCHAR(100) NOT NULL,
  amount         DECIMAL(10,2) NOT NULL,
  status         ENUM('INITIATED','SUCCESS','FAILED','REFUND_PENDING','REFUNDED') NOT NULL DEFAULT 'INITIATED',
  created_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (payment_id),
  UNIQUE KEY uq_payment_txn (gateway, gateway_txn_id),
  KEY idx_payment_booking (booking_id),
  CONSTRAINT fk_payment_booking FOREIGN KEY (booking_id) REFERENCES booking(booking_id)
) ENGINE=InnoDB;

-- Idempotency ledger: the UNIQUE key makes a duplicate webhook delivery a no-op.
CREATE TABLE payment_webhook_event (
  event_pk         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  gateway          VARCHAR(30)  NOT NULL,
  gateway_event_id VARCHAR(100) NOT NULL,      -- id sent by the gateway, unique per event
  payment_id       BIGINT UNSIGNED NULL,
  event_type       VARCHAR(50)  NOT NULL,      -- 'payment.captured', 'payment.failed'
  payload          JSON NOT NULL,
  received_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  processed_at     DATETIME NULL,
  PRIMARY KEY (event_pk),
  UNIQUE KEY uq_webhook_event (gateway, gateway_event_id),
  CONSTRAINT fk_pwe_payment FOREIGN KEY (payment_id) REFERENCES payment(payment_id)
) ENGINE=InnoDB;
