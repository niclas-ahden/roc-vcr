app [main!] {
    pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.20.0/X73hGh05nNTkDHU06FHC0YfFaQB1pimX7gncRcao5mU.tar.br",
    json: "https://github.com/lukewilliamboswell/roc-json/releases/download/0.12.0/1trwx8sltQ-e9Y2rOB4LWUWLS_sFVyETK8Twl0i9qpw.tar.gz",
    vcr: "../../package/main.roc",
}

import pf.File
import pf.Http
import json.Json
import vcr.Vcr

## This test triggers: "VCR Replay mode: No matching interaction found"
## by trying to replay from an empty cassette
main! = |_args|
    cassette_dir = "test/crash/cassettes"
    cassette_name = "empty"

    # Create cassette directory
    _ = File.write_bytes!([], "$(cassette_dir)/.keep")

    # Write valid but empty cassette using proper JSON encoding
    empty_cassette : Vcr.StoredCassette
    empty_cassette = { name: cassette_name, interactions: [] }
    json_bytes = Encode.to_bytes(empty_cassette, Json.utf8)
    _ = File.write_bytes!(json_bytes, "$(cassette_dir)/$(cassette_name).json")

    # Try to use VCR in Replay mode with no interactions
    cfg = {
        mode: Replay,
        cassette_dir,
        remove_headers: [],
        replace_sensitive_data: [],
        before_record: |i| i,
        before_replay: |i| i,
        skip_interactions: 0,
        http_send!: Http.send!,
        file_read!: File.read_bytes!,
        file_write!: File.write_bytes!,
        file_delete!: File.delete!,
    }

    client! = Vcr.init!(cfg, cassette_name)

    # This request will crash because no matching interaction exists
    _ = client!({
        method: GET,
        uri: "https://example.com/not-recorded",
        headers: [],
        body: [],
        timeout_ms: NoTimeout,
    })

    Ok({})
