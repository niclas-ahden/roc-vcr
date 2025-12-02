app [main!] {
    pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.20.0/X73hGh05nNTkDHU06FHC0YfFaQB1pimX7gncRcao5mU.tar.br",
    vcr: "../package/main.roc",
}

import pf.Stdout
import pf.Http
import pf.File
import vcr.Vcr

main! = |_args|
    _ = Stdout.line!("=== VCR Example ===")?

    # Configure VCR - pass Http.send! directly, no adapter needed!
    vcr_config = {
        mode: Once,
        cassette_dir: "cassettes",
        remove_headers: ["Authorization", "X-Api-Key"],
        replace_sensitive_data: [
            { find: "secret-token", replace: "[REDACTED]" },
        ],
        before_record: |interaction| interaction,
        before_replay: |interaction| interaction,
        skip_interactions: 0,
        http_send!: Http.send!,
        file_read!: File.read_bytes!,
        file_write!: File.write_bytes!,
        file_delete!: File.delete!,
    }

    # Initialize VCR client with a cassette name
    client! = Vcr.init!(vcr_config, "example_cassette")

    # Make HTTP requests using the VCR client
    # First run will make real HTTP requests and save them
    # Subsequent runs will replay from the cassette
    request = {
        method: GET,
        uri: "https://api.github.com/repos/roc-lang/roc",
        headers: [{ name: "User-Agent", value: "roc-vcr-example" }],
        body: [],
        timeout_ms: NoTimeout,
    }

    response = client!(request)?

    _ = Stdout.line!("Response status: $(Num.to_str(response.status))")?

    # Parse the response body
    when Str.from_utf8(response.body) is
        Ok(body_str) ->
            # Just show first 200 chars of response
            preview =
                if Str.count_utf8_bytes(body_str) > 200 then
                    Str.to_utf8(body_str)
                    |> List.take_first(200)
                    |> Str.from_utf8
                    |> Result.with_default("")
                    |> Str.concat("...")
                else
                    body_str
            Stdout.line!("Response preview: $(preview)")

        Err(_) ->
            Stdout.line!("Could not decode response body as UTF-8")
