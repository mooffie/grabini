/**
 * Downloads a single segment.
 *
 * For technical info, see https://developer.mozilla.org/en-US/docs/Web/HTTP/Range_requests
 */

bool debug_mode = false;

const int NET_BUFSZ = 1024*20;

public errordomain DownloaderError {
    NO_PARTIAL_CONTENT,
    SEGMENT_SPLIT_ERR,
    TODO,
}

public enum SegmentState {
    IDLE,
    DOWNLOADING,
    DONE,
}

public enum DownloadingState { // @todo: add "Segment" in front.
    WAITING,
    RECEIVING,
    ERROR,
}

public class Segment {

    public string url { get; protected set; }

    public bool enabled = true;

    // where this segment starts and ends.
    public int64 offs_start { get; protected set; }     // [0..)
    public int64 offs_finish { get; protected set; }    // -1 means "to end".
    public int64 offs_current { get; protected set; default = -1; }  // -1 means not initialized.

    // identifies this segment in messages.
    public int id = 0;
    private static int last_id = 0;

    public Segment.full(Downloader owner,
      string url,
      int64 offs_start,
      int64 offs_finish,
      int64 offs_current
    ) {
        this(owner);
        this.url = url;
        this.offs_start = offs_start;
        this.offs_finish = offs_finish;
        this.offs_current = offs_current;
    }

    protected weak Downloader owner;

    protected Speedometer speed;

    public bool is_error() {
        return state == DOWNLOADING && downloading_state == ERROR;
    }

    public SegmentState state {
        private set {
            _state = value;
            if (_state == DONE)
                owner.on_segment_done(this);
        }
        public get {
            switch (_state) {

            case IDLE:
                if (!is_initializing() &&
                        (offs_current >= offs_finish))
                    return DONE;
                else
                    return IDLE;

            default:  // DOWNLOADING, DONE
                return _state;

            }
        }
    }
    private SegmentState _state = IDLE;

    /**
     * Only valid when state == DOWNLOADING.
     */
    public DownloadingState downloading_state {
        public get {
            return _downloading_state;
        }
        private set {
            _downloading_state = value;
            if (_downloading_state == ERROR)
                owner.on_segment_error(this);
        }
    }
    private DownloadingState _downloading_state;

    public Segment(Downloader owner) {
        this.owner = owner;
        speed = new Speedometer();
        id = ++last_id;
    }

    private bool is_initializing() {
        return offs_finish == -1 || offs_current == -1;
    }

    public bool is_done() {   // @todo: remove?
        return state == DONE;
    }

    /**
     * Returns download progress.
     */
    public double calc_percent() {
        if (is_initializing())
            return 0;
        return (offs_current - offs_start) * 1.0 / (offs_finish - offs_start);
    }

    /**
     * Returns download progress, as integer usually in range [0, 100].
     *
     * May return beyond 100, if we're downloading past the bounds (due
     * to bug or intentionally). It never returns 100 if state != DONE:
     * in this case it returns 99 in order not to confuse the user.
    */
    public int calc_percent_int() {
        int i = (int)(calc_percent() * 100);

        if (i == 100 && !is_done())
            return 99;
        else
            return i;
    }

    /**
     * A short comment to appear in the INI file.
     */
    public string render_ini_description() {
        if (is_done())
            return "Done.";
        else if (offs_current <= offs_start)  // "<" covers -1.
            return "Not yet started.";
        else
            return "%d%% completed.".printf(calc_percent_int());
    }

    public int calc_speed() {
        return speed.calc_speed();
    }

    public int64 calc_eta() {
        //return Utils.format_interval(speed.calc_eta(offs_finish - offs_current));
        return speed.calc_eta(offs_finish - offs_current);
    }

    /**
     * Used by outside code when splitting segments.
     *
     * We need it since we don't provide write access to offs_finish.
     */
    public void trim() {
        offs_finish = offs_current;
    }

    public async void fetch() {

        state = DOWNLOADING;

        downloading_state = WAITING;

        var sess = new Soup.Session();
        sess.user_agent = "Casterton/2.0";
        var msg = new Soup.Message("GET", url);

        if (offs_current == -1)
            offs_current = offs_start;

        msg.request_headers.set_range(offs_current,
            (offs_finish == -1)
                ? -1
                : offs_finish - 1
        );

        if (debug_mode) Debug.print_request(msg, id);

        InputStream strm;

        try {
            strm = yield sess.send_async(msg, null);
        } catch (Error e) {
            // when network is off:
            // "Error in send_async(): Error resolving “example.com”: Temporary failure in name resolution (code: 1, domain: g-resolver-error-quark)"
            p("[Segment #%d] Error in send_async(): %s (code: %s, domain: %s)", id, e.message, e.code.to_string(), e.domain.to_string());
            downloading_state = ERROR;
            return;
        }

        {
            int64 dummy, total_size;
            if (!msg.response_headers.get_content_range (out dummy, out dummy, out total_size)) {
                Debug.print_response(msg, id);
                p("[Segment #%d] The server doesn't seem to support partial content. Or perhaps it doesn't support parallel downloads. Use '-d' to see the response headers. I'm skipping this segment. I'll try it again when some other segment finishes. (Server's response code: %u (%s)).", id, msg.status_code, msg.reason_phrase);
                downloading_state = ERROR;
                return;
            }
            else if (offs_finish != -1) {
                int64 expected_size = offs_finish - offs_current;
                int64 content_length = msg.response_headers.get_content_length();
                if (content_length != expected_size) {
                    Debug.print_response(msg, id);
                    p("[Segment #%d] The server returns a different amount of bytes (%lld) than expected (%lld).
                      Use '-d' to see the response headers. I'm skipping this segment.", id, content_length, expected_size);
                      downloading_state = ERROR;
                      return;
                }
            }

            // Now we know the exact total size, not an estimation. We don't really have to know
            // it: this is just to make the .ini file show the real size.
            if (offs_finish == -1)
                offs_finish = total_size;
        }

        if (debug_mode) Debug.print_response(msg, id);

        downloading_state = RECEIVING;

        try {
            for (;;) {
                Bytes bf = yield strm.read_bytes_async(NET_BUFSZ, Priority.DEFAULT, null);
                owner.iostream.seek(offs_current, SeekType.SET);
                owner.output.write_bytes(bf);
                offs_current += bf.length;
                speed.record(offs_current);
                //p("rd ln: %i (currofs: %d)", bf.length, offs_current);
                if (bf.length == 0) break;
            }
        }
        catch (Error e) {
            // After 1 minute w/o reponse:
            // "Error: Socket I/O timed out (code: 24, domain: g-io-error-quark)"
            p("[Segment #%d] Error: %s (code: %s, domain: %s)", id, e.message, e.code.to_string(), e.domain.to_string());
            downloading_state = ERROR;
            return;
        }

        state = DONE;
    }

}
