/**
 * Doanloads a file by splitting it into several 'Segment's
 * and asking each segment to download.
 */

const int MAX_SEGMENTS = 50;

public class Downloader {

    public string? url;
    private string pathname_ini;
    private string pathname_output;

    public string[] headers;

    public int64? estimated_size;        // null if missing, we do HEAD in this case.
    public int requested_seg_count = 4;  // split into 4 segment by default.

    private Segment[] segments;

    public FileIOStream iostream;

    /////////////////////////

    // Fired when download is done.
    public signal void has_finished(bool success);

    ////////////////////////

    public Downloader(string? url, string pathname_ini, string pathname_output) {
        this.url = url;
        this.pathname_ini = pathname_ini;
        this.pathname_output = pathname_output;

        this.segments = {};
        this.headers = {};
    }

    public OutputStream output {
        get {
            return iostream.output_stream;  // see note in doc about who owns who.
        }
    }

    int tries = 1;
    int MAX_TRIES = 0;  // How many times to retry download after failure.

    public void on_segment_error(Segment seg) {

       if (!has_active_downloads()) { // otherwise, let on_segment_done() handle things for us.

          if (tries <= MAX_TRIES) {
              p("Retrying to download feailed segments (%d of %d tries)", tries, MAX_TRIES);
              tries++;
              // @todo: it's best to wait a bit.
              start_downloads();
          }
          else
              has_finished(false);  // give up.

       }
    }

    public void on_segment_done(Segment seg) {

        if (is_done())
            // We've downloaded all segments. Notify listeners that we're done.
            has_finished(true);
        else {
            // Restart downloading of segments stuck on downloding error.
            //
            // Some servers don't support parallel downloads so we have
            // do download the segments sequentialy.
            start_downloads();
        }

    }

    private void create_segments(int64 total_size) {

        int64 seg_size = total_size / requested_seg_count;

        for (int i = 0; i < requested_seg_count; i++) {

            bool is_last = (i == requested_seg_count - 1);

            int64 offs_start = i * seg_size;
            int64 offs_finish = (i + 1) * seg_size;

            // In case we have an estimated size, or in case of rounding error,
            // let the last segment fill-in its exact length:
            if (is_last)
                offs_finish = -1;

            segments += new Segment.full(this, url, offs_start, offs_finish, -1);

        }
    }

    private int64 find_total_size() {
        return new SizeQuery(url).get_size();
    }

    public void split_segment(int seg_no, int parts) {
        assert(seg_no > 0);
        assert(seg_no <= segments.length);
        assert(parts >= 2);

        p("Splitting segment #%d into %d parts.", seg_no, parts);

        seg_no--;  // make it zero-based.
        var seg = segments[seg_no];
        if (seg.offs_finish == -1)
            throw new DownloaderError.SEGMENT_SPLIT_ERR("Cannot split a segment whose size is unknown.");
        if (seg.offs_current >= seg.offs_finish)
            throw new DownloaderError.SEGMENT_SPLIT_ERR("Cannot split a segment that's been fully downloaded already.");

        bool do_close = (seg.offs_current != seg.offs_start);  // Close the current segment?
        int64 hole_start = seg.offs_current;
        int64 hole_finish = seg.offs_finish;

        int n_pos;  // Where to insert the new elements.

        if (do_close) {
            // We can't write 'seg.offs_finish = seg.offs_current', as we don't
            // have write acess to that property. trim() does this for us.
            seg.trim();
            n_pos = seg_no + 1;
            segments = Utils.extend_array(segments, n_pos, parts);
        }
        else {
            segments[seg_no] = null;
            n_pos = seg_no;
            segments = Utils.extend_array(segments, n_pos, parts - 1);
        }

        int64 part_size = (hole_finish - hole_start) / parts;

        for (int i = 0; i < parts; i++) {
            bool is_last = (i == parts - 1);

            int64 offs_start = hole_start + (i * part_size);
            int64 offs_finish = is_last ? hole_finish : hole_start + ((i + 1) * part_size);

            segments[n_pos + i] = new Segment.full(this, url, offs_start, offs_finish, -1);
        }
    }

    public void go(bool ini_only) {
        load_ini_file();
        if (segments.length == 0) {
            create_segments(estimated_size ?? find_total_size());
        }

        if (ini_only) {
            save_ini_file();
            return;
        }

        try {
            create_output_file();
        } catch (Error e) {
            p("*** " + e.message);
            return;  // will mainloop kick in?
        }

        start_downloads();
    }

    public bool is_done() {
        foreach (var seg in segments) {
            if (seg.enabled && !seg.is_done())
                return false;
        }
        return true;
    }

    public bool is_all_error() {
        foreach (var seg in segments) {
            if (!seg.is_error())
                return false;
        }
        return true;
    }

    public bool has_active_downloads() {
        foreach (var seg in segments) {
            if (seg.state == DOWNLOADING && !seg.is_error())
                return true;
        }
        return false;
    }

    private void start_downloads() {

        foreach (var seg in segments) {
            if (seg.enabled &&
                    (seg.state == IDLE || seg.is_error())) {
                p("[Re]starting segment #%d.", seg.id);
                seg.fetch.begin();
            }
        }

    }

    private void create_output_file() throws Error {
        File file = File.new_for_path(pathname_output);
        try {
            // If file doesn't exist.
            iostream = file.create_readwrite(NONE);
        } catch (Error e) {
            if (e is IOError.EXISTS)
                // It exists.
                iostream = file.open_readwrite();
            else
                throw e;
        }
    }

    private void load_ini_file() throws KeyFileError, FileError {
        p("Looking for %s ...", pathname_ini);
        var kf = new KeyFile();

        try {
            // From the documentation:
            //
            // "This function will never return a G_KEY_FILE_ERROR_NOT_FOUND
            //  error. If the file is not found, G_FILE_ERROR_NOENT is returned."
            kf.load_from_file(pathname_ini, KEEP_COMMENTS);
            p("Found. Loaded.");
        }
        catch (FileError e) {
            if (e is FileError.NOENT) {
                p("INI Not found.");
                return;
            }
            else
                throw e;
        }

        url = kf.get_string("default", "url");
        headers = kf.get_string_list("default", "headers");

        for (int i = 1; i <= MAX_SEGMENTS; i++) {
            string seg_group = "segment" + i.to_string();
            if (kf.has_group(seg_group)) {

                int64 offs_start = kf.get_int64(seg_group, "offs_start");
                int64 offs_finish = kf.get_int64(seg_group, "offs_finish");
                int64 offs_current = kf.get_int64(seg_group, "offs_current");

                var seg = new Segment.full(this, url, offs_start, offs_finish, offs_current);
                seg.enabled = kf.get_boolean(seg_group, "enabled");
                segments += seg;
            }
        }
    }

    public void save_ini_file() throws KeyFileError, FileError {
        var kf = new KeyFile();
        kf.set_comment(null, null, " Feel free to modify this data and re-launch he program.");
        kf.set_string("default", "url", url);
        kf.set_string_list("default", "headers", {"one","two"});

        var i = 1;
        foreach (var seg in segments) {
            string seg_group = "segment" + i.to_string();
            kf.set_int64(seg_group, "offs_start", seg.offs_start);
            kf.set_int64(seg_group, "offs_finish", seg.offs_finish);
            kf.set_int64(seg_group, "offs_current", seg.offs_current);
            kf.set_boolean(seg_group, "enabled", seg.enabled);
            kf.set_comment(seg_group, null, " " + seg.render_ini_description());
            i++;
        }

        kf.save_to_file(pathname_ini);
    }

    private string render_segment_percent(Segment seg) {
        return "%2d%%".printf(seg.calc_percent_int());
    }

    private string render_segment_download_progress(Segment seg) {
        string prc = render_segment_percent(seg);
        switch(seg.downloading_state) {
        case WAITING:
            return "[Waiting]";
        case ERROR:
            return "[Error:%s]".printf(prc);
        case RECEIVING:
        default:
            return prc;
        }
    }

    private string render_segment_progress(Segment seg) {
        switch (seg.state) {
        case DONE:
            return "[Done]";
        case DOWNLOADING:
            return render_segment_download_progress(seg);
        case IDLE:
            return "[Idle:%s]".printf(render_segment_percent(seg));
        default:
            return "?";
        }
    }

    private string render_segment_speed(Segment seg) {
        if (seg.state == DOWNLOADING && seg.downloading_state == RECEIVING)
            return "%dkb/s[%s]".printf(seg.calc_speed(), Utils.format_interval(seg.calc_eta()));
        else
            return "-";
    }

    private void print_progress_line() {
        string ln = "Progress: ";
        foreach (var seg in segments) {
            ln += " " + render_segment_progress(seg) + " ";
        }
        ln += "   ##   ";
        foreach (var seg in segments) {
            ln += " " + render_segment_speed(seg) + " ";
        }

        p("%s", ln);
    }

    // Called every X seconds.
    public void periodic() {
        save_ini_file();
        print_progress_line();
    }

}

public class SizeQuery {

    protected string url;

    public SizeQuery(string url) {
        this.url = url;
    }

    public int64 get_size() {
        var sess = new Soup.Session();
        var msg = new Soup.Message("HEAD", url);
        if (debug_mode) Debug.print_request(msg);
        sess.send(msg);
        if (debug_mode) Debug.print_response(msg);
        return msg.response_headers.get_content_length();
    }

}
