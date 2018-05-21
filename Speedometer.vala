/**
 * Calculates download speed.
 */

// If we haven't received data during the last SPD_STALE seconds,
// it means communication is stalled and we refuse to calculate the speed.
const int SPD_STALE = 3;

const int SPD_QUEUE_LEN = 8;

/**
 * The speedometer works by recording, in a queue, points in time and
 * the amount of bytes received at each point. It calculates the speed
 * by comparing the oldest and the newest point.
 */
struct SpeedMeasureRec {
    int64 seconds;
    int64 bytes;
}

public class Speedometer {

    private Timer epoch;

    private SpeedMeasureRec[] recs;
    private int recs_len;

    public Speedometer() {
        recs = new SpeedMeasureRec[SPD_QUEUE_LEN];
        recs_len = 0;
        epoch = new Timer();
        epoch.start();
    }

    private int64 get_elapsed() {
        epoch.stop();
        return (int64)epoch.elapsed();
    }

    public void record(int64 bytes) {

        var rec = SpeedMeasureRec() {
            seconds = get_elapsed(),
            bytes = bytes
        };

        if (rec.seconds != recs[0].seconds) {
            recs.move(0, 1, recs.length - 1);
            recs[0] = rec;
            if (recs_len < recs.length)
                recs_len++;
        }

    }

    public void debug__print() {
        for (int i = 0; i < recs_len; i++) {
            var rec = recs[i];
            // https://www.google.co.il/search?q=printf+int64
            p("{%lld, %lld}", rec.seconds, rec.bytes);
        }
        p("");
    }

    /**
     * Calculates the speed, in kb/s.
     *
     * Returns 0 if can't calculate.
     */
    public int calc_speed() {
        if (recs_len < 2)
            return 0;
        if (get_elapsed() - recs[0].seconds > SPD_STALE)
            return 0;

        int64 seconds = recs[0].seconds - recs[recs_len - 1].seconds;
        int64 bytes = recs[0].bytes - recs[recs_len - 1].bytes;

        return (int) ( (bytes / seconds) / 1024 );
    }

    /**
     * How long, in seconds, it would take to transfer 'size' bytes.
     *
     * Returns 0 if can't calculate.
     */
    public int64 calc_eta(int64 size) {
        var speed = calc_speed();
        if (speed != 0)
            return (size / 1024) / speed;
        else
            return 0;
    }

}
