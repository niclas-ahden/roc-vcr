app [main!] {
    pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.20.0/X73hGh05nNTkDHU06FHC0YfFaQB1pimX7gncRcao5mU.tar.br",
    vcr: "../../package/main.roc",
}

import pf.File
import pf.Http
import vcr.Vcr

## This test triggers: "VCR: Failed to decode cassette"
## by creating a malformed JSON cassette file
main! = |_args|
    cassette_dir = "test/crash/cassettes"
    cassette_name = "malformed"

    # Create cassette directory
    _ = File.write_bytes!([], "$(cassette_dir)/.keep")

    # Write malformed JSON to cassette file
    _ = File.write_bytes!(Str.to_utf8("{ this is not valid json }"), "$(cassette_dir)/$(cassette_name).json")

    # Try to use VCR in Replay mode - should crash when decoding
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

    # This request will trigger cassette load, which will crash on decode
    _ = client!({
        method: GET,
        uri: "https://example.com",
        headers: [],
        body: [],
        timeout_ms: NoTimeout,
    })

    Ok({})
