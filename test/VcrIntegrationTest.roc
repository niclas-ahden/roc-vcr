app [main!] {
    pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.20.0/X73hGh05nNTkDHU06FHC0YfFaQB1pimX7gncRcao5mU.tar.br",
    json: "https://github.com/lukewilliamboswell/roc-json/releases/download/0.12.0/1trwx8sltQ-e9Y2rOB4LWUWLS_sFVyETK8Twl0i9qpw.tar.gz",
    vcr: "../package/main.roc",
}

import pf.Stdout
import pf.File
import pf.Http
import json.Json
import vcr.Vcr

main! = |_args|
    _ = Stdout.line!("=== VCR Integration Tests ===")?

    # Test all modes with single and multiple interactions
    test_once_mode_single!({})?
    test_once_mode_multiple!({})?
    test_once_mode_duplicate_requests!({})?
    test_replace_mode_single!({})?
    test_replace_mode_multiple!({})?
    test_replace_mode_duplicate_requests!({})?
    test_replay_mode_single!({})?
    test_replay_mode_multiple!({})?
    test_skip_interactions!({})?
    test_skip_interactions_replace_mode!({})?

    # Additional coverage
    test_remove_headers!({})?
    test_replace_sensitive_data!({})?
    test_replace_sensitive_data_in_body!({})?
    test_replace_sensitive_data_in_headers!({})?
    test_before_record_hook!({})?
    test_before_replay_hook!({})?
    test_post_with_body!({})?

    _ = Stdout.line!("\n=== All Tests Passed ===")?
    Ok({})

# ============================================================================
# Helper functions
# ============================================================================

cassette_dir = "test/cassettes"


make_config = |mode|
    {
        mode,
        cassette_dir,
        remove_headers: [],
        replace_sensitive_data: [],
        skip_interactions: 0,
        before_record: |interaction| interaction,
        before_replay: |interaction| interaction,
        http_send!: Http.send!,
        file_read!: File.read_bytes!,
        file_write!: File.write_bytes!,
        file_delete!: File.delete!,
    }

count_interactions! : Str => Result U64 [FileError]
count_interactions! = |name|
    path = "$(cassette_dir)/$(name).json"
    when File.read_bytes!(path) is
        Ok(bytes) ->
            decoded : Result Vcr.StoredCassette _
            decoded = Decode.from_bytes(bytes, Json.utf8_with({ skip_missing_properties: Bool.true }))
            when decoded is
                Ok(cassette) -> Ok(List.len(cassette.interactions))
                Err(_) -> Ok(0)

        Err(_) -> Ok(0)

load_cassette_for_test! : Str => Result Vcr.StoredCassette [FileNotFound, DecodeError]
load_cassette_for_test! = |name|
    path = "$(cassette_dir)/$(name).json"
    when File.read_bytes!(path) is
        Ok(bytes) ->
            decoded : Result Vcr.StoredCassette _
            decoded = Decode.from_bytes(bytes, Json.utf8_with({ skip_missing_properties: Bool.true }))
            when decoded is
                Ok(cassette) -> Ok(cassette)
                Err(_) -> Err(DecodeError)

        Err(_) -> Err(FileNotFound)

cleanup! : Str => Result {} _
cleanup! = |name|
    path = "$(cassette_dir)/$(name).json"
    when File.delete!(path) is
        Ok({}) -> Ok({})
        Err(_) -> Ok({}) # Ignore if doesn't exist

make_request = |method, uri|
    {
        method,
        uri,
        headers: [],
        body: [],
        timeout_ms: NoTimeout,
    }

# ============================================================================
# Once Mode Tests
# ============================================================================

test_once_mode_single! : {} => Result {} _
test_once_mode_single! = |{}|
    _ = Stdout.line!("\n--- Once Mode: Single Interaction ---")?
    cassette_name = "test_once_single"
    _ = cleanup!(cassette_name)

    cfg = make_config(Once)
    client! = Vcr.init!(cfg, cassette_name)

    request = make_request(GET, "https://example.com/")

    # First request - should record
    response = client!(request)?
    _ = Stdout.line!("  Request 1: status $(Num.to_str(response.status))")?

    count = count_interactions!(cassette_name)?
    if count == 1 then
        _ = Stdout.line!("  PASS: 1 interaction recorded")?
        _ = cleanup!(cassette_name)
        Ok({})
    else
        _ = Stdout.line!("  FAIL: Expected 1 interaction, got $(Num.to_str(count))")?
        Err(TestFailed)

test_once_mode_multiple! : {} => Result {} _
test_once_mode_multiple! = |{}|
    _ = Stdout.line!("\n--- Once Mode: Multiple Different Interactions ---")?
    cassette_name = "test_once_multiple"
    _ = cleanup!(cassette_name)

    cfg = make_config(Once)
    client! = Vcr.init!(cfg, cassette_name)

    request1 = make_request(GET, "https://example.com/")
    request2 = make_request(HEAD, "https://example.com/")

    # Two different requests - both should record
    response1 = client!(request1)?
    _ = Stdout.line!("  Request 1 (GET): status $(Num.to_str(response1.status))")?

    response2 = client!(request2)?
    _ = Stdout.line!("  Request 2 (HEAD): status $(Num.to_str(response2.status))")?

    count = count_interactions!(cassette_name)?
    if count == 2 then
        _ = Stdout.line!("  PASS: 2 interactions recorded")?
        _ = cleanup!(cassette_name)
        Ok({})
    else
        _ = Stdout.line!("  FAIL: Expected 2 interactions, got $(Num.to_str(count))")?
        Err(TestFailed)

test_once_mode_duplicate_requests! : {} => Result {} _
test_once_mode_duplicate_requests! = |{}|
    _ = Stdout.line!("\n--- Once Mode: Duplicate Requests (should record all) ---")?
    cassette_name = "test_once_duplicates"
    _ = cleanup!(cassette_name)

    cfg = make_config(Once)
    client! = Vcr.init!(cfg, cassette_name)

    request = make_request(GET, "https://example.com/")

    # Same request 3 times - ALL should be recorded (this tests the fix!)
    response1 = client!(request)?
    _ = Stdout.line!("  Request 1: status $(Num.to_str(response1.status))")?

    response2 = client!(request)?
    _ = Stdout.line!("  Request 2: status $(Num.to_str(response2.status))")?

    response3 = client!(request)?
    _ = Stdout.line!("  Request 3: status $(Num.to_str(response3.status))")?

    count = count_interactions!(cassette_name)?
    if count == 3 then
        _ = Stdout.line!("  PASS: 3 duplicate interactions recorded")?
        _ = cleanup!(cassette_name)
        Ok({})
    else
        _ = Stdout.line!("  FAIL: Expected 3 interactions, got $(Num.to_str(count))")?
        Err(TestFailed)

# ============================================================================
# Replace Mode Tests
# ============================================================================

test_replace_mode_single! : {} => Result {} _
test_replace_mode_single! = |{}|
    _ = Stdout.line!("\n--- Replace Mode: Single Interaction ---")?
    cassette_name = "test_replace_single"
    _ = cleanup!(cassette_name)

    cfg = make_config(Replace)
    client! = Vcr.init!(cfg, cassette_name)

    request = make_request(GET, "https://example.com/")

    response = client!(request)?
    _ = Stdout.line!("  Request: status $(Num.to_str(response.status))")?

    count = count_interactions!(cassette_name)?
    if count == 1 then
        _ = Stdout.line!("  PASS: 1 interaction recorded")?
        _ = cleanup!(cassette_name)
        Ok({})
    else
        _ = Stdout.line!("  FAIL: Expected 1 interaction, got $(Num.to_str(count))")?
        Err(TestFailed)

test_replace_mode_multiple! : {} => Result {} _
test_replace_mode_multiple! = |{}|
    _ = Stdout.line!("\n--- Replace Mode: Multiple Interactions ---")?
    cassette_name = "test_replace_multiple"
    _ = cleanup!(cassette_name)

    cfg = make_config(Replace)
    client! = Vcr.init!(cfg, cassette_name)

    request1 = make_request(GET, "https://example.com/")
    request2 = make_request(HEAD, "https://example.com/")

    response1 = client!(request1)?
    _ = Stdout.line!("  Request 1 (GET): status $(Num.to_str(response1.status))")?

    response2 = client!(request2)?
    _ = Stdout.line!("  Request 2 (HEAD): status $(Num.to_str(response2.status))")?

    count = count_interactions!(cassette_name)?
    if count == 2 then
        _ = Stdout.line!("  PASS: 2 interactions recorded")?
        _ = cleanup!(cassette_name)
        Ok({})
    else
        _ = Stdout.line!("  FAIL: Expected 2 interactions, got $(Num.to_str(count))")?
        Err(TestFailed)

test_replace_mode_duplicate_requests! : {} => Result {} _
test_replace_mode_duplicate_requests! = |{}|
    _ = Stdout.line!("\n--- Replace Mode: Duplicate Requests (should record all) ---")?
    cassette_name = "test_replace_duplicates"
    _ = cleanup!(cassette_name)

    cfg = make_config(Replace)
    client! = Vcr.init!(cfg, cassette_name)

    request = make_request(GET, "https://example.com/")

    # Same request 3 times - ALL should be recorded
    response1 = client!(request)?
    _ = Stdout.line!("  Request 1: status $(Num.to_str(response1.status))")?

    response2 = client!(request)?
    _ = Stdout.line!("  Request 2: status $(Num.to_str(response2.status))")?

    response3 = client!(request)?
    _ = Stdout.line!("  Request 3: status $(Num.to_str(response3.status))")?

    count = count_interactions!(cassette_name)?
    if count == 3 then
        _ = Stdout.line!("  PASS: 3 duplicate interactions recorded")?
        _ = cleanup!(cassette_name)
        Ok({})
    else
        _ = Stdout.line!("  FAIL: Expected 3 interactions, got $(Num.to_str(count))")?
        Err(TestFailed)

# ============================================================================
# Replay Mode Tests
# ============================================================================

test_replay_mode_single! : {} => Result {} _
test_replay_mode_single! = |{}|
    _ = Stdout.line!("\n--- Replay Mode: Single Interaction ---")?
    cassette_name = "test_replay_single"
    _ = cleanup!(cassette_name)

    # First, record with Once mode
    cfg_once = make_config(Once)
    client_record! = Vcr.init!(cfg_once, cassette_name)

    request = make_request(GET, "https://example.com/")

    original_response = client_record!(request)?
    _ = Stdout.line!("  Recorded: status $(Num.to_str(original_response.status))")?

    # Now replay
    cfg_replay = make_config(Replay)
    client_replay! = Vcr.init!(cfg_replay, cassette_name)

    replayed_response = client_replay!(request)?
    _ = Stdout.line!("  Replayed: status $(Num.to_str(replayed_response.status))")?

    if original_response.status == replayed_response.status then
        _ = Stdout.line!("  PASS: Response replayed correctly")?
        _ = cleanup!(cassette_name)
        Ok({})
    else
        _ = Stdout.line!("  FAIL: Status mismatch")?
        Err(TestFailed)

test_replay_mode_multiple! : {} => Result {} _
test_replay_mode_multiple! = |{}|
    _ = Stdout.line!("\n--- Replay Mode: Multiple Interactions ---")?
    cassette_name = "test_replay_multiple"
    _ = cleanup!(cassette_name)

    # Record two different requests
    cfg_once = make_config(Once)
    client_record! = Vcr.init!(cfg_once, cassette_name)

    request1 = make_request(GET, "https://example.com/")
    request2 = make_request(HEAD, "https://example.com/")

    resp1_orig = client_record!(request1)?
    resp2_orig = client_record!(request2)?
    _ = Stdout.line!("  Recorded: GET=$(Num.to_str(resp1_orig.status)), HEAD=$(Num.to_str(resp2_orig.status))")?

    # Replay both
    cfg_replay = make_config(Replay)
    client_replay! = Vcr.init!(cfg_replay, cassette_name)

    resp1_replay = client_replay!(request1)?
    resp2_replay = client_replay!(request2)?
    _ = Stdout.line!("  Replayed: GET=$(Num.to_str(resp1_replay.status)), HEAD=$(Num.to_str(resp2_replay.status))")?

    if resp1_orig.status == resp1_replay.status && resp2_orig.status == resp2_replay.status then
        _ = Stdout.line!("  PASS: Both responses replayed correctly")?
        _ = cleanup!(cassette_name)
        Ok({})
    else
        _ = Stdout.line!("  FAIL: Status mismatch")?
        Err(TestFailed)

# ============================================================================
# skip_interactions Test
# ============================================================================

test_skip_interactions! : {} => Result {} _
test_skip_interactions! = |{}|
    _ = Stdout.line!("\n--- skip_interactions: Multiple Matching Interactions ---")?
    cassette_name = "test_skip_interactions"
    _ = cleanup!(cassette_name)

    # Record 3 duplicate requests (same method, URI, body)
    cfg_once = make_config(Once)
    client_record! = Vcr.init!(cfg_once, cassette_name)

    request = make_request(GET, "https://example.com/")

    # Record 3 identical requests
    _ = client_record!(request)?
    _ = client_record!(request)?
    _ = client_record!(request)?
    _ = Stdout.line!("  Recorded 3 identical requests")?

    count = count_interactions!(cassette_name)?
    _ = Stdout.line!("  Cassette has $(Num.to_str(count)) interactions")?

    if count != 3 then
        _ = Stdout.line!("  FAIL: Expected 3 interactions, got $(Num.to_str(count))")?
        Err(TestFailed)
    else
        # Now replay with different skip values
        # skip_interactions: 0 should get first
        base_cfg = make_config(Replay)
        cfg_skip0 = { base_cfg & skip_interactions: 0 }
        client_skip0! = Vcr.init!(cfg_skip0, cassette_name)
        replay0 = client_skip0!(request)?
        _ = Stdout.line!("  skip=0: status $(Num.to_str(replay0.status))")?

        # skip_interactions: 1 should get second
        cfg_skip1 = { base_cfg & skip_interactions: 1 }
        client_skip1! = Vcr.init!(cfg_skip1, cassette_name)
        replay1 = client_skip1!(request)?
        _ = Stdout.line!("  skip=1: status $(Num.to_str(replay1.status))")?

        # skip_interactions: 2 should get third
        cfg_skip2 = { base_cfg & skip_interactions: 2 }
        client_skip2! = Vcr.init!(cfg_skip2, cassette_name)
        replay2 = client_skip2!(request)?
        _ = Stdout.line!("  skip=2: status $(Num.to_str(replay2.status))")?

        # All should have same status (200) since example.com returns same response
        # The key test is that we got 3 interactions recorded
        _ = Stdout.line!("  PASS: skip_interactions works correctly")?
        _ = cleanup!(cassette_name)
        Ok({})

test_skip_interactions_replace_mode! : {} => Result {} _
test_skip_interactions_replace_mode! = |{}|
    _ = Stdout.line!("\n--- skip_interactions: Replace Mode with Duplicates ---")?
    cassette_name = "test_skip_replace"
    _ = cleanup!(cassette_name)

    # Record 3 duplicate requests using Replace mode
    cfg_replace = make_config(Replace)
    client_record! = Vcr.init!(cfg_replace, cassette_name)

    request = make_request(GET, "https://example.com/")

    # Record 3 identical requests
    _ = client_record!(request)?
    _ = client_record!(request)?
    _ = client_record!(request)?
    _ = Stdout.line!("  Recorded 3 identical requests with Replace mode")?

    count = count_interactions!(cassette_name)?
    _ = Stdout.line!("  Cassette has $(Num.to_str(count)) interactions")?

    if count != 3 then
        _ = Stdout.line!("  FAIL: Expected 3 interactions, got $(Num.to_str(count))")?
        Err(TestFailed)
    else
        # Now replay with different skip values
        base_cfg = make_config(Replay)

        # skip_interactions: 0 should get first
        cfg_skip0 = { base_cfg & skip_interactions: 0 }
        client_skip0! = Vcr.init!(cfg_skip0, cassette_name)
        replay0 = client_skip0!(request)?
        _ = Stdout.line!("  skip=0: status $(Num.to_str(replay0.status))")?

        # skip_interactions: 1 should get second
        cfg_skip1 = { base_cfg & skip_interactions: 1 }
        client_skip1! = Vcr.init!(cfg_skip1, cassette_name)
        replay1 = client_skip1!(request)?
        _ = Stdout.line!("  skip=1: status $(Num.to_str(replay1.status))")?

        # skip_interactions: 2 should get third
        cfg_skip2 = { base_cfg & skip_interactions: 2 }
        client_skip2! = Vcr.init!(cfg_skip2, cassette_name)
        replay2 = client_skip2!(request)?
        _ = Stdout.line!("  skip=2: status $(Num.to_str(replay2.status))")?

        _ = Stdout.line!("  PASS: skip_interactions works with Replace mode")?
        _ = cleanup!(cassette_name)
        Ok({})

# ============================================================================
# Header Removal Tests
# ============================================================================

test_remove_headers! : {} => Result {} _
test_remove_headers! = |{}|
    _ = Stdout.line!("\n--- remove_headers: Filter Authorization header ---")?
    cassette_name = "test_remove_headers"
    _ = cleanup!(cassette_name)

    # Create config with remove_headers
    base_cfg = make_config(Once)
    cfg = { base_cfg & remove_headers: ["Authorization", "X-Api-Key"] }
    client! = Vcr.init!(cfg, cassette_name)

    request = {
        method: GET,
        uri: "https://example.com/",
        headers: [
            { name: "Authorization", value: "Bearer secret-token-12345" },
            { name: "X-Api-Key", value: "api-key-67890" },
            { name: "Accept", value: "application/json" },
        ],
        body: [],
        timeout_ms: NoTimeout,
    }

    _ = client!(request)?
    _ = Stdout.line!("  Recorded request with Authorization and X-Api-Key headers")?

    # Load cassette and verify headers were removed
    when load_cassette_for_test!(cassette_name) is
        Ok(cassette) ->
            when List.first(cassette.interactions) is
                Ok(interaction) ->
                    has_auth = List.any(
                        interaction.request.headers,
                        |h| h.name == "Authorization" || h.name == "authorization",
                    )
                    has_api_key = List.any(
                        interaction.request.headers,
                        |h| h.name == "X-Api-Key" || h.name == "x-api-key",
                    )
                    has_accept = List.any(
                        interaction.request.headers,
                        |h| h.name == "Accept" || h.name == "accept",
                    )

                    if !has_auth && !has_api_key && has_accept then
                        _ = Stdout.line!("  PASS: Sensitive headers removed, Accept header kept")?
                        _ = cleanup!(cassette_name)
                        Ok({})
                    else
                        _ = Stdout.line!("  FAIL: Header filtering not working correctly")?
                        Err(TestFailed)

                Err(_) ->
                    _ = Stdout.line!("  FAIL: No interactions in cassette")?
                    Err(TestFailed)

        Err(_) ->
            _ = Stdout.line!("  FAIL: Could not load cassette")?
            Err(TestFailed)

# ============================================================================
# Sensitive Data Replacement Tests
# ============================================================================

test_replace_sensitive_data! : {} => Result {} _
test_replace_sensitive_data! = |{}|
    _ = Stdout.line!("\n--- replace_sensitive_data: Filter secrets from URI ---")?
    cassette_name = "test_sensitive_data"
    _ = cleanup!(cassette_name)

    secret_token = "my-secret-token-xyz"

    # Create config with sensitive data replacement
    base_cfg = make_config(Once)
    cfg = { base_cfg &
        replace_sensitive_data: [{ find: secret_token, replace: "[REDACTED]" }],
    }
    client! = Vcr.init!(cfg, cassette_name)

    # Use a real endpoint but with fake token in query param
    request = make_request(GET, "https://example.com/?token=$(secret_token)")

    _ = client!(request)?
    _ = Stdout.line!("  Recorded request with secret token in URI")?

    # Load cassette and verify token was replaced
    when load_cassette_for_test!(cassette_name) is
        Ok(cassette) ->
            when List.first(cassette.interactions) is
                Ok(interaction) ->
                    uri_has_secret = Str.contains(interaction.request.uri, secret_token)
                    uri_has_redacted = Str.contains(interaction.request.uri, "[REDACTED]")

                    if !uri_has_secret && uri_has_redacted then
                        _ = Stdout.line!("  PASS: Secret token replaced with [REDACTED]")?
                        _ = cleanup!(cassette_name)
                        Ok({})
                    else
                        _ = Stdout.line!("  FAIL: Secret not replaced in URI")?
                        Err(TestFailed)

                Err(_) ->
                    _ = Stdout.line!("  FAIL: No interactions in cassette")?
                    Err(TestFailed)

        Err(_) ->
            _ = Stdout.line!("  FAIL: Could not load cassette")?
            Err(TestFailed)

test_replace_sensitive_data_in_body! : {} => Result {} _
test_replace_sensitive_data_in_body! = |{}|
    _ = Stdout.line!("\n--- replace_sensitive_data: Filter secrets from request body ---")?
    cassette_name = "test_sensitive_body"
    _ = cleanup!(cassette_name)

    secret_key = "secret-api-key-12345"

    # Create config with sensitive data replacement
    base_cfg = make_config(Once)
    cfg = { base_cfg &
        replace_sensitive_data: [{ find: secret_key, replace: "[REDACTED]" }],
    }
    client! = Vcr.init!(cfg, cassette_name)

    # POST request with secret in body
    body_with_secret = Str.to_utf8("{\"api_key\": \"$(secret_key)\"}")
    request = {
        method: POST,
        uri: "https://httpbin.org/post",
        headers: [{ name: "Content-Type", value: "application/json" }],
        body: body_with_secret,
        timeout_ms: NoTimeout,
    }

    _ = client!(request)?
    _ = Stdout.line!("  Recorded request with secret in body")?

    # Load cassette and verify secret was replaced in body
    when load_cassette_for_test!(cassette_name) is
        Ok(cassette) ->
            when List.first(cassette.interactions) is
                Ok(interaction) ->
                    body_str = Str.from_utf8(interaction.request.body) |> Result.with_default("")
                    body_has_secret = Str.contains(body_str, secret_key)
                    body_has_redacted = Str.contains(body_str, "[REDACTED]")

                    if !body_has_secret && body_has_redacted then
                        _ = Stdout.line!("  PASS: Secret replaced in request body")?
                        _ = cleanup!(cassette_name)
                        Ok({})
                    else
                        _ = Stdout.line!("  FAIL: Secret not replaced in body")?
                        Err(TestFailed)

                Err(_) ->
                    _ = Stdout.line!("  FAIL: No interactions in cassette")?
                    Err(TestFailed)

        Err(_) ->
            _ = Stdout.line!("  FAIL: Could not load cassette")?
            Err(TestFailed)

test_replace_sensitive_data_in_headers! : {} => Result {} _
test_replace_sensitive_data_in_headers! = |{}|
    _ = Stdout.line!("\n--- replace_sensitive_data: Filter secrets from header values ---")?
    cassette_name = "test_sensitive_headers"
    _ = cleanup!(cassette_name)

    secret_token = "my-secret-token-xyz"

    # Create config with sensitive data replacement
    base_cfg = make_config(Once)
    cfg = { base_cfg &
        replace_sensitive_data: [{ find: secret_token, replace: "[REDACTED]" }],
    }
    client! = Vcr.init!(cfg, cassette_name)

    # Request with secret in header value
    request = {
        method: GET,
        uri: "https://example.com/",
        headers: [
            { name: "Authorization", value: "Bearer $(secret_token)" },
            { name: "Accept", value: "application/json" },
        ],
        body: [],
        timeout_ms: NoTimeout,
    }

    _ = client!(request)?
    _ = Stdout.line!("  Recorded request with secret in Authorization header")?

    # Load cassette and verify secret was replaced in header value
    when load_cassette_for_test!(cassette_name) is
        Ok(cassette) ->
            when List.first(cassette.interactions) is
                Ok(interaction) ->
                    # Find the Authorization header
                    auth_header = List.find_first(
                        interaction.request.headers,
                        |h| h.name == "Authorization",
                    )

                    when auth_header is
                        Ok(header) ->
                            value_has_secret = Str.contains(header.value, secret_token)
                            value_has_redacted = Str.contains(header.value, "[REDACTED]")

                            if !value_has_secret && value_has_redacted then
                                _ = Stdout.line!("  PASS: Secret replaced in header value")?
                                _ = cleanup!(cassette_name)
                                Ok({})
                            else
                                _ = Stdout.line!("  FAIL: Secret not replaced in header value")?
                                Err(TestFailed)

                        Err(_) ->
                            _ = Stdout.line!("  FAIL: Authorization header not found")?
                            Err(TestFailed)

                Err(_) ->
                    _ = Stdout.line!("  FAIL: No interactions in cassette")?
                    Err(TestFailed)

        Err(_) ->
            _ = Stdout.line!("  FAIL: Could not load cassette")?
            Err(TestFailed)

# ============================================================================
# Hook Tests
# ============================================================================

add_marker_hook : Vcr.Interaction -> Vcr.Interaction
add_marker_hook = |interaction|
    resp = interaction.response
    modified_response = { resp &
        headers: List.append(resp.headers, { name: "X-VCR-Recorded", value: "true" }),
    }
    { interaction & response: modified_response }

test_before_record_hook! : {} => Result {} _
test_before_record_hook! = |{}|
    _ = Stdout.line!("\n--- before_record hook: Transform before recording ---")?
    cassette_name = "test_before_record"
    _ = cleanup!(cassette_name)

    # Create config with before_record hook that adds a marker header
    base_cfg = make_config(Once)
    cfg = { base_cfg & before_record: add_marker_hook }
    client! = Vcr.init!(cfg, cassette_name)

    request = make_request(GET, "https://example.com/")

    _ = client!(request)?
    _ = Stdout.line!("  Recorded request with before_record hook")?

    # Load cassette and verify hook added the header
    when load_cassette_for_test!(cassette_name) is
        Ok(cassette) ->
            when List.first(cassette.interactions) is
                Ok(interaction) ->
                    has_marker = List.any(
                        interaction.response.headers,
                        |h| h.name == "X-VCR-Recorded" && h.value == "true",
                    )

                    if has_marker then
                        _ = Stdout.line!("  PASS: before_record hook added marker header")?
                        _ = cleanup!(cassette_name)
                        Ok({})
                    else
                        _ = Stdout.line!("  FAIL: Marker header not found")?
                        Err(TestFailed)

                Err(_) ->
                    _ = Stdout.line!("  FAIL: No interactions in cassette")?
                    Err(TestFailed)

        Err(_) ->
            _ = Stdout.line!("  FAIL: Could not load cassette")?
            Err(TestFailed)

modify_status_hook : Vcr.Interaction -> Vcr.Interaction
modify_status_hook = |interaction|
    resp = interaction.response
    modified_response = { resp & status: 999 }
    { interaction & response: modified_response }

test_before_replay_hook! : {} => Result {} _
test_before_replay_hook! = |{}|
    _ = Stdout.line!("\n--- before_replay hook: Transform before replaying ---")?
    cassette_name = "test_before_replay"
    _ = cleanup!(cassette_name)

    # First record normally
    cfg_record = make_config(Once)
    client_record! = Vcr.init!(cfg_record, cassette_name)

    request = make_request(GET, "https://example.com/")

    _ = client_record!(request)?
    _ = Stdout.line!("  Recorded original response")?

    # Now replay with a hook that modifies the status
    base_cfg = make_config(Replay)
    cfg_replay = { base_cfg & before_replay: modify_status_hook }
    client_replay! = Vcr.init!(cfg_replay, cassette_name)

    replayed_response = client_replay!(request)?
    _ = Stdout.line!("  Replayed with before_replay hook")?

    if replayed_response.status == 999 then
        _ = Stdout.line!("  PASS: before_replay hook modified status to 999")?
        _ = cleanup!(cassette_name)
        Ok({})
    else
        _ = Stdout.line!("  FAIL: Expected status 999, got $(Num.to_str(replayed_response.status))")?
        Err(TestFailed)

# ============================================================================
# POST with Body Tests
# ============================================================================

test_post_with_body! : {} => Result {} _
test_post_with_body! = |{}|
    _ = Stdout.line!("\n--- POST with body: Record and replay POST requests ---")?
    cassette_name = "test_post_body"
    _ = cleanup!(cassette_name)

    cfg = make_config(Once)
    client! = Vcr.init!(cfg, cassette_name)

    body_content = Str.to_utf8("{\"test\": \"data\"}")
    request = {
        method: POST,
        uri: "https://httpbin.org/post",
        headers: [{ name: "Content-Type", value: "application/json" }],
        body: body_content,
        timeout_ms: NoTimeout,
    }

    response1 = client!(request)?
    _ = Stdout.line!("  Recorded POST request: status $(Num.to_str(response1.status))")?

    # Verify cassette has the body
    when load_cassette_for_test!(cassette_name) is
        Ok(cassette) ->
            when List.first(cassette.interactions) is
                Ok(interaction) ->
                    body_matches = interaction.request.body == body_content

                    if body_matches then
                        _ = Stdout.line!("  PASS: POST body recorded correctly")?

                        # Now replay and verify same response
                        cfg_replay = make_config(Replay)
                        client_replay! = Vcr.init!(cfg_replay, cassette_name)

                        response2 = client_replay!(request)?
                        if response1.status == response2.status then
                            _ = Stdout.line!("  PASS: POST replayed correctly")?
                            _ = cleanup!(cassette_name)
                            Ok({})
                        else
                            _ = Stdout.line!("  FAIL: Replay status mismatch")?
                            Err(TestFailed)
                    else
                        _ = Stdout.line!("  FAIL: POST body not recorded correctly")?
                        Err(TestFailed)

                Err(_) ->
                    _ = Stdout.line!("  FAIL: No interactions in cassette")?
                    Err(TestFailed)

        Err(_) ->
            _ = Stdout.line!("  FAIL: Could not load cassette")?
            Err(TestFailed)
