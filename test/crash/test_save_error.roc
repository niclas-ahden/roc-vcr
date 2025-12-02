app [main!] {
    pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.20.0/X73hGh05nNTkDHU06FHC0YfFaQB1pimX7gncRcao5mU.tar.br",
    vcr: "../../package/main.roc",
}

import pf.File
import pf.Http
import vcr.Vcr

## This test triggers: "VCR: Failed to save cassette"
## by trying to save to a read-only directory
##
## Setup: The bash script creates a read-only directory before running this test
main! = |_args|
    cassette_dir = "test/crash/cassettes_readonly"
    cassette_name = "will_fail_to_save"

    # Use Once mode to trigger recording (no existing cassette)
    cfg = {
        mode: Once,
        cassette_dir,
        remove_headers: [],
        replace_sensitive_data: [],
        before_record: |i| i,
        before_replay: |i| i,
        skip_interactions: 0,
        http_send!: mock_http!,
        file_read!: File.read_bytes!,
        file_write!: File.write_bytes!,
        file_delete!: File.delete!,
    }

    client! = Vcr.init!(cfg, cassette_name)

    # This request will succeed (mock), but saving will crash
    _ = client!({
        method: GET,
        uri: "https://example.com",
        headers: [],
        body: [],
        timeout_ms: NoTimeout,
    })

    Ok({})

# Mock HTTP that returns a response without making real request
mock_http! : _ => Result Vcr.Response []
mock_http! = |_req|
    Ok({
        status: 200,
        headers: [],
        body: Str.to_utf8("mock response"),
    })
