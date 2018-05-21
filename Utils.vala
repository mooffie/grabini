
[ PrintfFormat ]   /* Otherwise pushing an "int?" pushes a pointer, not the integer.
                      And "%d" won't generate error when passing an int64. */
void p(string fmt, ...) {
    var vl = va_list();
    stdout.vprintf(fmt + "\n", vl);
}

namespace Utils {

    bool is_valid_http_uri(string uri_)  // @todo: "https:" should be invalid
    {
        var uri = new Soup.URI(uri_);
        return (uri != null) && (uri.scheme == "http" || uri.scheme == "https");
    }

    bool file_exists(string pathname) {
        return FileUtils.test(pathname, FileTest.EXISTS);
    }

    string? url_to_filename(string url)
    {
        var s = Path.get_basename(url);
        s = Uri.unescape_string(s, "/");
        if (s == null ||
                s.length > 120 ||
                (s.length > 80 && !(" " in s) && !("_" in s)))
            return null;
        return s;
    }

    string string_to_gist(string s)
    {
        var md5 = Checksum.compute_for_string(MD5, s);
        // Base64 gives mostly letters, which are easier for humans to discern than digits, so we use it:
        var b64 = Base64.encode(md5.data)[0:12];  // @todo: char[] is converted to uchar[] automatically?
        return b64;
    }

    public string format_interval(int64 time) {  // in seconds.

      int64 secs, mins, hours, days;
      secs = time % 60;
      time /= 60;
      mins = time % 60;
      time /= 60;
      hours = time % 24;
      time /= 24;
      days = time;

      string s = "";
      if (days != 0)
        s = s + days.to_string() + "d";
      if (hours != 0)
        s = s + hours.to_string() + "h";
      if (mins != 0)
        s = s + mins.to_string() + "m";
      if (secs != 0 && (days == 0 && hours == 0 && mins < 10))
        s = s + secs.to_string() + "s";

      return s;
    }

    public T[] extend_array<T>(T[] src, int pos, int count) {
        T[] dst = new T[src.length + count];

        for (int i = 0; i < pos; i++)
            dst[i] = src[i];

        for (int i = 0; i < src.length - pos; i++) {
            dst[pos + count + i] = src[pos + i];
        }
        return dst;
    }


} // namespace
