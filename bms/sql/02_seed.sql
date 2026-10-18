USE bms;

INSERT INTO city (name, state) VALUES ('Bengaluru','Karnataka'), ('Mumbai','Maharashtra');
INSERT INTO theatre (city_id, name, address) VALUES
 (1,'PVR: Orion Mall, Rajajinagar','Dr Rajkumar Rd, Rajajinagar, Bengaluru'),
 (1,'INOX: Garuda Mall','Magrath Rd, Ashok Nagar, Bengaluru');
INSERT INTO screen (theatre_id, name) VALUES (1,'Audi 1'),(1,'Audi 2'),(2,'Screen 1');
INSERT INTO seat_category (name) VALUES ('Classic'),('Prime'),('Recliner');

-- Small demo layout: rows A-B Classic, row C Recliner, 4 seats each (Audi 1 = screen 1)
INSERT INTO seat (screen_id,row_label,seat_number,category_id) VALUES
 (1,'A',1,1),(1,'A',2,1),(1,'A',3,1),(1,'A',4,1),
 (1,'B',1,2),(1,'B',2,2),(1,'B',3,2),(1,'B',4,2),
 (1,'C',1,3),(1,'C',2,3),(1,'C',3,3),(1,'C',4,3);

INSERT INTO language (name) VALUES ('Hindi'),('English'),('Kannada');
INSERT INTO format (name) VALUES ('2D'),('3D'),('IMAX 2D');
INSERT INTO movie (title,duration_min,certificate,release_date) VALUES
 ('Dhurandhar',214,'A','2025-12-05'),
 ('Avatar: Fire and Ash',195,'UA','2025-12-19'),
 ('Kantara: Chapter 1',168,'UA','2025-10-02');

-- Shows are generated relative to today so the demo always has "next 7 days" of data.
INSERT INTO `show` (screen_id,movie_id,language_id,format_id,show_date,start_time,end_time) VALUES
 (1,1,1,1,CURDATE(),'09:30:00','13:04:00'),
 (1,1,1,1,CURDATE(),'14:00:00','17:34:00'),
 (1,1,1,1,CURDATE(),'19:00:00','22:34:00'),
 (2,2,2,3,CURDATE(),'10:00:00','13:15:00'),
 (2,2,1,3,CURDATE(),'15:00:00','18:15:00'),
 (2,3,3,1,CURDATE(),'20:00:00','22:48:00'),
 (1,1,1,1,CURDATE()+INTERVAL 1 DAY,'10:00:00','13:34:00'),
 (2,2,2,3,CURDATE()+INTERVAL 1 DAY,'18:00:00','21:15:00'),
 (3,3,3,1,CURDATE(),'12:00:00','14:48:00');   -- other theatre: must NOT appear for theatre 1

INSERT INTO show_price (show_id,category_id,price) VALUES
 (1,1,150),(1,2,220),(1,3,450),
 (2,1,180),(2,2,250),(2,3,500),
 (3,1,200),(3,2,300),(3,3,600);

-- Materialise seat inventory for show 1 (a job does this for every show at scheduling time)
INSERT INTO show_seat (show_id, seat_id)
SELECT 1, seat_id FROM seat WHERE screen_id = 1;

INSERT INTO app_user (name,email,phone) VALUES
 ('Asha Rao','asha@example.com','+919800000001'),
 ('Vikram Shah','vikram@example.com','+919800000002');

-- Asha: a CONFIRMED booking of A1, A2 (BOOKED)
INSERT INTO booking (user_id,show_id,status,total_amount,hold_expires_at)
VALUES (1,1,'CONFIRMED',300.00,NOW());
UPDATE show_seat SET status='BOOKED', booking_id=1
 WHERE show_id=1 AND seat_id IN (SELECT seat_id FROM seat WHERE screen_id=1 AND row_label='A' AND seat_number IN (1,2));

-- Vikram: PENDING hold on B1 for 5 minutes
INSERT INTO booking (user_id,show_id,status,total_amount,hold_expires_at)
VALUES (2,1,'PENDING',220.00,NOW()+INTERVAL 5 MINUTE);
UPDATE show_seat SET status='HELD', booking_id=2, hold_expires_at=NOW()+INTERVAL 5 MINUTE, version=version+1
 WHERE show_id=1 AND seat_id IN (SELECT seat_id FROM seat WHERE screen_id=1 AND row_label='B' AND seat_number=1);

INSERT INTO payment (booking_id,gateway,gateway_txn_id,amount,status) VALUES
 (1,'razorpay','pay_Nx001',300.00,'SUCCESS'),
 (2,'razorpay','pay_Nx002',220.00,'INITIATED');
INSERT INTO payment_webhook_event (gateway,gateway_event_id,payment_id,event_type,payload,processed_at) VALUES
 ('razorpay','evt_001',1,'payment.captured','{"payment_id":"pay_Nx001","amount":30000}',NOW());
