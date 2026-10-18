"""50 threads race for the SAME seat (show 1, seat 9). Exactly one must win."""
import pymysql, threading
wins, lock = [], threading.Lock()
def attempt(uid):
    c = pymysql.connect(user='t', password='t', database='bms', autocommit=False)
    cur = c.cursor()
    cur.execute("""UPDATE show_seat SET status='HELD', booking_id=%s,
                   hold_expires_at=NOW()+INTERVAL 5 MINUTE, version=version+1
                   WHERE show_id=1 AND seat_id=9
                   AND (status='AVAILABLE' OR (status='HELD' AND hold_expires_at<NOW()))""", (uid,))
    won = cur.rowcount == 1
    c.commit(); c.close()
    if won:
        with lock: wins.append(uid)
ts = [threading.Thread(target=attempt, args=(1 if i%2 else 2,)) for i in range(50)]
[t.start() for t in ts]; [t.join() for t in ts]
print("winners:", len(wins))
assert len(wins) == 1
