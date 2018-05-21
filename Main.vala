/**
 * Contains main().
 *
 * Creates and runs a Downloader object.
 */

// Holds command line options.
namespace Options {
    bool debug = false;
    int64 estimated_size = 0;
    [CCode (array_length = false, array_null_terminated = true)]
    string[]? headers = null;
    bool ini_only = false;
    int segments = 4;
    string? output_explicit = null;
    string? split_segment = null;
}

const OptionEntry[] entries = {
    { "debug", 'd', 0, NONE, ref Options.debug, "Print debug info", null },
    { "estimate", 'e', 0, INT64, ref Options.estimated_size, "Give your estimation for the file size; if provided, this saves one HEAD request.", "size_in_bytes" },
    { "header", 'H', 0, STRING_ARRAY, ref Options.headers, "Extra header", "HEADER" },
    { "ini-only", 0, 0, NONE, ref Options.ini_only, "Don't download. Just write the .ini file. (Use '-e' if you also want to save one HEAD request.)" },
    { "segments", 'j', 0, INT, ref Options.segments, "Number of segments to download simultaneously (default: 4).", "NUM" },
    { "output-document", 'O', 0, STRING, ref Options.output_explicit, "Set the name of the output file (instead of guessing it)", "FILENAME" },
    { "split-segment", 0, 0, STRING, ref Options.split_segment, "Split sement number N to M parts", "N:M" },
    { null },
};

const string INI_EXT = ".grab.ini";

const string args_desc = "url OR /path/to/inifile OR /path/to/partially/downloded/file";

/**
 * Figures out the meaning of the 1st arg: url, ini file, or output file.
 */
bool figure_out_arg(string arg, string? output_explicit, out string? url, out string pathname_ini, out string pathname_output)
{
    url = null;
    pathname_ini = null;
    pathname_output = null;

    if (Utils.is_valid_http_uri(arg)) {  // it's URL
        url = arg;
        pathname_output = output_explicit ??
                          Utils.url_to_filename(url) ??
                          "grab-%s.bin".printf(Utils.string_to_gist(url));
        pathname_ini = pathname_output + INI_EXT;
        if (Utils.file_exists(pathname_ini)) {
            // URL (and various options) will be taken from the INI file, not the command-line.
            url = null;
        }
    }
    else {
        if (!Utils.file_exists(arg)) {
            p("Error: You haven't provided a valid URL. Instead, you may provide the path to the INI file, or to the partially downloaded file. You provided neither.");
            return false;
        }
        if (arg.has_suffix(INI_EXT)) { // it's an existing .ini file.
            pathname_ini = arg;
            pathname_output = pathname_ini[0 : pathname_ini.length - INI_EXT.length];
        }
        else {
            // It's the partially downloaded file.
            pathname_output = arg;
            pathname_ini = pathname_output + INI_EXT;
            if (!Utils.file_exists(pathname_ini)) {
                p("I assume you provided the path to a partially downloaded file (as it doesn't have the extension '%s'). But I can't find the correspoding INI file (%s)", INI_EXT, pathname_ini);
                return false;
            }
        }
    }
    return true;
}

static void main(string[] args) {

    {
        var opt_context = new OptionContext (args_desc);
        opt_context.set_help_enabled (true);
        opt_context.add_main_entries (entries, null);
        opt_context.parse (ref args);
    }

    if (args.length != 2) {
        p("Error: syntax is: %s [options] %s", args[0], args_desc);
        return;
    }

    //////////////////////////////////////////////

    string? url = null;
    string pathname_ini = null;
    string pathname_output = null;

    if (!figure_out_arg(args[1], Options.output_explicit, out url, out pathname_ini, out pathname_output))
        return;

    p("Output file: %s", pathname_output);
    p("INI file: %s", pathname_ini);
    p("URL: %s", url ?? "< will be taken from the INI file >");

    //////////////////////////////////////////////

    p("---");

    MainLoop loop = new MainLoop ();

    debug_mode = Options.debug;

    var dldr = new Downloader(url, pathname_ini, pathname_output);

    if (Options.estimated_size != 0) {
        // @todo: sanity check.
        dldr.estimated_size = Options.estimated_size;
    }
    dldr.requested_seg_count = Options.segments;

    if (Options.split_segment != null) {
      // @todo: C compiler gives werror when I write `string nums[] = ...`
      string[] nums = Options.split_segment.split(":");
      assert(nums.length == 2);
      int seg_no = int.parse(nums[0]);
      int seg_parts = int.parse(nums[1]);
      dldr.go(true); // create the segments.
      dldr.split_segment(seg_no, seg_parts);
      dldr.save_ini_file();
      return;
    }

    dldr.go(Options.ini_only);

    if (Options.ini_only) {
        return;
    }

    if (dldr.is_done()) {
        p("Already downloaded.");
        // Skip the main loop.
        return;
    }

    dldr.has_finished.connect((obj, success) => {
        dldr.periodic();
        p(success ? "OK" : "FAILED");
        loop.quit();
    });

    var timer = new TimeoutSource(5000);  // update display every 5 seconds.
    timer.set_callback(() => {
        dldr.periodic();
        return true;
    });
    timer.attach(null);

    loop.run();
}
