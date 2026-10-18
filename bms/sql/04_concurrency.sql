-- Reference statements the application runs. ? = bind parameter.
USE bms;

-- (1) HOLD seats (pessimistic, ordered row locks -> no deadlocks, no double-hold)
START TRANSACTION;
  SELECT show_seat_id FROM show_seat
   WHERE show_id = ? AND seat_id IN (?, ?)
     AND (status = 'AVAILABLE' OR (status = 'HELD' AND hold_expires_at < NOW()))
   ORDER BY seat_id
   FOR UPDATE SKIP LOCKED;            -- app: if rows returned < seats requested -> ROLLBACK, "seat taken"
  INSERT INTO booking (user_id, show_id, total_amount, hold_expires_at)
   VALUES (?, ?, ?, NOW() + INTERVAL 5 MINUTE);
  UPDATE show_seat
     SET status='HELD', booking_id = LAST_INSERT_ID(),
         hold_expires_at = NOW() + INTERVAL 5 MINUTE, version = version + 1
   WHERE show_seat_id IN (?, ?);
COMMIT;

-- (1b) Same thing optimistically (no explicit lock; one atomic statement per seat).
-- ROW_COUNT() = 0 means somebody else won.
UPDATE show_seat
   SET status='HELD', booking_id=?, hold_expires_at=NOW()+INTERVAL 5 MINUTE, version=version+1
 WHERE show_id=? AND seat_id=? AND version=?
   AND (status='AVAILABLE' OR (status='HELD' AND hold_expires_at < NOW()));

-- (2) Idempotent payment webhook
START TRANSACTION;
  INSERT IGNORE INTO payment_webhook_event (gateway, gateway_event_id, event_type, payload)
   VALUES ('razorpay', ?, 'payment.captured', ?);
  -- ROW_COUNT() = 0 -> duplicate delivery: COMMIT and return 200, do nothing else.
  UPDATE payment SET status='SUCCESS' WHERE gateway='razorpay' AND gateway_txn_id=? AND status='INITIATED';
  UPDATE show_seat SET status='BOOKED', hold_expires_at=NULL
   WHERE booking_id=? AND status='HELD';        -- ownership check: seat reassigned after expiry -> 0 rows
  -- ROW_COUNT() = seats in booking -> UPDATE booking SET status='CONFIRMED' WHERE booking_id=? AND status='PENDING';
  -- otherwise -> payment.status='REFUND_PENDING', booking.status='EXPIRED'
  UPDATE payment_webhook_event SET processed_at = NOW() WHERE gateway='razorpay' AND gateway_event_id=?;
COMMIT;

-- (3) Sweeper (every few seconds): release expired holds
UPDATE show_seat SET status='AVAILABLE', booking_id=NULL, hold_expires_at=NULL, version=version+1
 WHERE status='HELD' AND hold_expires_at < NOW() LIMIT 1000;
UPDATE booking SET status='EXPIRED' WHERE status='PENDING' AND hold_expires_at < NOW();
