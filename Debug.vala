/**
 * Debugging utils.
 */

namespace Debug {

string http_ver(Soup.HTTPVersion v) {
    switch(v) {
    case @1_0:
        return "HTTP/1.0";
    case @1_1:
        return "HTTP/1.1";
    default:
        return "HTTP/???";
    }
}

void print_headers(Soup.MessageHeaders hdrs) {
    hdrs.foreach ((name, val) => {
        stdout.printf ("%s: %s\n", name, val);
    });
}

void print_request(Soup.Message msg, int? seg_id = null) {
    if (seg_id != null)
        p("---[Segment #%d] request---", seg_id);
    else
        p("---request---");
    p("%s %s %s", msg.method, msg.uri.to_string(true), http_ver(msg.http_version));
    print_headers(msg.request_headers);
    p("");
}

void print_response(Soup.Message msg, int? seg_id = null) {
    if (seg_id != null)
        p("---[Segment #%d] response---", seg_id);
    else
        p("---response---");
    p("%s %u %s", http_ver(msg.http_version), msg.status_code, msg.reason_phrase);
    print_headers(msg.response_headers);
    p("");
}

} // namespace
