app [main!] {
    pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.20.0/X73hGh05nNTkDHU06FHC0YfFaQB1pimX7gncRcao5mU.tar.br",
    json: "https://github.com/lukewilliamboswell/roc-json/releases/download/0.12.0/1trwx8sltQ-e9Y2rOB4LWUWLS_sFVyETK8Twl0i9qpw.tar.gz",
    vcr: "../../package/main.roc",
}

import pf.File
import pf.Http
import json.Json
import vcr.Vcr

## This test triggers: "VCR: Failed to delete cassette"
## by trying to delete a cassette in a read-only directory
##
## Setup: The bash script creates a cassette in a read-only directory before running this test
main! = |_args|
    cassette_dir = "test/crash/cassettes_readonly"
    cassette_name = "cannot_delete"

    # Use Replace mode which will try to delete existing cassette
    cfg = {
        mode: Replace,
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

    # init! will crash when trying to delete the existing cassette
    client! = Vcr.init!(cfg, cassette_name)

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
