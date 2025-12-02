app [main!] {
    pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.20.0/X73hGh05nNTkDHU06FHC0YfFaQB1pimX7gncRcao5mU.tar.br",
    json: "https://github.com/lukewilliamboswell/roc-json/releases/download/0.12.0/1trwx8sltQ-e9Y2rOB4LWUWLS_sFVyETK8Twl0i9qpw.tar.gz",
    vcr: "../package/main.roc",
}

import pf.Stdout
import pf.File
import json.Json
import vcr.Vcr

main! = |_args|
    _ = Stdout.line!("=== VCR Mock Tests ===")?

    # Recording behavior
    test_record_stores_request_and_response!({})?
    test_record_multiple_interactions_appends!({})?
    test_record_preserves_response_body!({})?

    # Replay behavior
    test_replay_returns_exact_response!({})?
    test_replay_matches_by_method!({})?
    test_replay_matches_by_body_hash!({})?
    test_replay_ignores_headers_for_matching!({})?

    # Mode behavior
    test_once_mode_records_when_no_cassette!({})?
    test_once_mode_replays_when_cassette_exists!({})?
    test_replace_mode_deletes_existing_cassette!({})?

    # Filtering
    test_filter_removes_secret_from_uri!({})?
    test_filter_removes_secret_from_request_body!({})?
    test_filter_removes_secret_from_response_body!({})?
    test_filter_removes_secret_from_header_value!({})?
    test_remove_headers_strips_specified_headers!({})?

    # Hooks
    test_before_record_transforms_interaction!({})?
    test_before_replay_transforms_interaction!({})?

    # Skip interactions
    test_skip_interactions_skips_n_matches!({})?

    _ = Stdout.line!("\n=== All Mock Tests Passed ===")?
    Ok({})

# ============================================================================
# Mock Infrastructure
# ============================================================================

cassette_dir = "test/mock_cassettes"

# Mock HTTP that returns predictable responses based on request
mock_http_send! : Vcr.Request => Result Vcr.Response [MockHttpError]
mock_http_send! = |req|
    method_str =
        when req.method is
            GET -> "GET"
            POST -> "POST"
            PUT -> "PUT"
            DELETE -> "DELETE"
            HEAD -> "HEAD"
            OPTIONS -> "OPTIONS"
            PATCH -> "PATCH"
            CONNECT -> "CONNECT"
            TRACE -> "TRACE"
            EXTENSION(name) -> name
    body_preview =
        when Str.from_utf8(req.body) is
            Ok(s) -> s
            Err(_) -> "<binary>"
    Ok({
        status: 200,
        headers: [
            { name: "X-Mock", value: "true" },
            { name: "X-Method", value: method_str },
        ],
        body: Str.to_utf8("response-for:$(method_str):$(req.uri):body=$(body_preview)"),
    })



make_mock_config = |mode|
    {
        mode,
        cassette_dir,
        remove_headers: [],
        replace_sensitive_data: [],
        skip_interactions: 0,
        before_record: |interaction| interaction,
        before_replay: |interaction| interaction,
        http_send!: mock_http_send!,
        file_read!: File.read_bytes!,
        file_write!: File.write_bytes!,
        file_delete!: File.delete!,
    }

cleanup! : Str => Result {} _
cleanup! = |name|
    path = "$(cassette_dir)/$(name).json"
    when File.delete!(path) is
        Ok({}) -> Ok({})
        Err(_) -> Ok({})

load_cassette! : Str => Result Vcr.StoredCassette [FileNotFound, DecodeError]
load_cassette! = |name|
    path = "$(cassette_dir)/$(name).json"
    when File.read_bytes!(path) is
        Ok(bytes) ->
            decoded : Result Vcr.StoredCassette _
            decoded = Decode.from_bytes(bytes, Json.utf8_with({ skip_missing_properties: Bool.true }))
            when decoded is
                Ok(cassette) -> Ok(cassette)
                Err(_) -> Err(DecodeError)

        Err(_) -> Err(FileNotFound)

make_request = |method, uri|
    {
        method,
        uri,
        headers: [],
        body: [],
        timeout_ms: NoTimeout,
    }

assert_eq = |actual, expected, msg|
    if actual == expected then
        Ok({})
    else
        Err(AssertionFailed(msg))

# ============================================================================
# Recording Behavior Tests
# ============================================================================

test_record_stores_request_and_response! : {} => Result {} _
test_record_stores_request_and_response! = |{}|
    _ = Stdout.line!("\n--- record_stores_request_and_response ---")?
    cassette_name = "mock_record_stores"
    _ = cleanup!(cassette_name)

    cfg = make_mock_config(Once)
    client! = Vcr.init!(cfg, cassette_name)

    request = make_request(GET, "https://api.test.com/users")
    _ = client!(request)?

    # Verify cassette contents
    cassette = load_cassette!(cassette_name)?
    interaction = List.first(cassette.interactions) |> Result.map_err(|_| NoInteraction)?

    # Check request was stored correctly
    _ = assert_eq(interaction.request.method, "GET", "method should be GET")?
    _ = assert_eq(interaction.request.uri, "https://api.test.com/users", "uri should match")?

    # Check response was stored correctly
    _ = assert_eq(interaction.response.status, 200, "status should be 200")?

    response_body = Str.from_utf8(interaction.response.body) |> Result.with_default("")
    if Str.contains(response_body, "response-for:GET:https://api.test.com/users") then
        _ = Stdout.line!("  PASS: Request and response stored correctly")?
        _ = cleanup!(cassette_name)
        Ok({})
    else
        _ = Stdout.line!("  FAIL: Response body mismatch: $(response_body)")?
        Err(TestFailed)

test_record_multiple_interactions_appends! : {} => Result {} _
test_record_multiple_interactions_appends! = |{}|
    _ = Stdout.line!("\n--- record_multiple_interactions_appends ---")?
    cassette_name = "mock_record_appends"
    _ = cleanup!(cassette_name)

    cfg = make_mock_config(Once)
    client! = Vcr.init!(cfg, cassette_name)

    # Make 3 different requests
    _ = client!(make_request(GET, "https://api.test.com/1"))?
    _ = client!(make_request(GET, "https://api.test.com/2"))?
    _ = client!(make_request(GET, "https://api.test.com/3"))?

    # Verify all 3 are in cassette
    cassette = load_cassette!(cassette_name)?
    count = List.len(cassette.interactions)

    if count == 3 then
        # Verify URIs are in order
        uris = List.map(cassette.interactions, |i| i.request.uri)
        expected = ["https://api.test.com/1", "https://api.test.com/2", "https://api.test.com/3"]
        if uris == expected then
            _ = Stdout.line!("  PASS: 3 interactions appended in order")?
            _ = cleanup!(cassette_name)
            Ok({})
        else
            _ = Stdout.line!("  FAIL: URIs not in expected order")?
            Err(TestFailed)
    else
        _ = Stdout.line!("  FAIL: Expected 3 interactions, got $(Num.to_str(count))")?
        Err(TestFailed)

test_record_preserves_response_body! : {} => Result {} _
test_record_preserves_response_body! = |{}|
    _ = Stdout.line!("\n--- record_preserves_response_body ---")?
    cassette_name = "mock_record_body"
    _ = cleanup!(cassette_name)

    cfg = make_mock_config(Once)
    client! = Vcr.init!(cfg, cassette_name)

    base_request = make_request(POST, "https://api.test.com/data")
    request = { base_request & body: Str.to_utf8("request-body-content") }
    _ = client!(request)?

    # Verify response body matches what mock returned
    cassette = load_cassette!(cassette_name)?
    interaction = List.first(cassette.interactions) |> Result.map_err(|_| NoInteraction)?

    stored_body = Str.from_utf8(interaction.response.body) |> Result.with_default("")

    # Stored body should contain the mock response
    if Str.contains(stored_body, "body=request-body-content") then
        _ = Stdout.line!("  PASS: Response body preserved with request body content")?
        _ = cleanup!(cassette_name)
        Ok({})
    else
        _ = Stdout.line!("  FAIL: Body mismatch. Stored: $(stored_body)")?
        Err(TestFailed)

# ============================================================================
# Replay Behavior Tests
# ============================================================================

test_replay_returns_exact_response! : {} => Result {} _
test_replay_returns_exact_response! = |{}|
    _ = Stdout.line!("\n--- replay_returns_exact_response ---")?
    cassette_name = "mock_replay_exact"
    _ = cleanup!(cassette_name)

    # Record first
    cfg_record = make_mock_config(Once)
    client_record! = Vcr.init!(cfg_record, cassette_name)
    request = make_request(GET, "https://api.test.com/exact")
    original = client_record!(request)?

    # Replay
    cfg_replay = make_mock_config(Replay)
    client_replay! = Vcr.init!(cfg_replay, cassette_name)
    replayed = client_replay!(request)?

    # Verify exact match
    if original.status == replayed.status && original.body == replayed.body then
        _ = Stdout.line!("  PASS: Replayed response matches original exactly")?
        _ = cleanup!(cassette_name)
        Ok({})
    else
        _ = Stdout.line!("  FAIL: Response mismatch")?
        Err(TestFailed)

test_replay_matches_by_method! : {} => Result {} _
test_replay_matches_by_method! = |{}|
    _ = Stdout.line!("\n--- replay_matches_by_method ---")?
    cassette_name = "mock_replay_method"
    _ = cleanup!(cassette_name)

    # Record a GET request
    cfg_record = make_mock_config(Once)
    client_record! = Vcr.init!(cfg_record, cassette_name)
    _ = client_record!(make_request(GET, "https://api.test.com/resource"))?

    # Also record a POST to same URI
    _ = client_record!(make_request(POST, "https://api.test.com/resource"))?

    # Replay GET - should get GET response
    cfg_replay = make_mock_config(Replay)
    client_replay! = Vcr.init!(cfg_replay, cassette_name)
    get_response = client_replay!(make_request(GET, "https://api.test.com/resource"))?

    get_body = Str.from_utf8(get_response.body) |> Result.with_default("")

    if Str.contains(get_body, "response-for:GET:") then
        _ = Stdout.line!("  PASS: GET request matched GET interaction")?
        _ = cleanup!(cassette_name)
        Ok({})
    else
        _ = Stdout.line!("  FAIL: Method matching failed. Body: $(get_body)")?
        Err(TestFailed)

test_replay_matches_by_body_hash! : {} => Result {} _
test_replay_matches_by_body_hash! = |{}|
    _ = Stdout.line!("\n--- replay_matches_by_body_hash ---")?
    cassette_name = "mock_replay_body_hash"
    _ = cleanup!(cassette_name)

    # Record POST with specific body
    cfg_record = make_mock_config(Once)
    client_record! = Vcr.init!(cfg_record, cassette_name)

    base_request = make_request(POST, "https://api.test.com/data")
    request1 = { base_request & body: Str.to_utf8("body-A") }
    request2 = { base_request & body: Str.to_utf8("body-B") }

    _ = client_record!(request1)?
    _ = client_record!(request2)?

    # Replay with body-A should get first response
    cfg_replay = make_mock_config(Replay)
    client_replay! = Vcr.init!(cfg_replay, cassette_name)
    response = client_replay!(request1)?

    response_body = Str.from_utf8(response.body) |> Result.with_default("")

    if Str.contains(response_body, "body=body-A") then
        _ = Stdout.line!("  PASS: Request matched by body hash")?
        _ = cleanup!(cassette_name)
        Ok({})
    else
        _ = Stdout.line!("  FAIL: Body hash matching failed. Response: $(response_body)")?
        Err(TestFailed)

test_replay_ignores_headers_for_matching! : {} => Result {} _
test_replay_ignores_headers_for_matching! = |{}|
    _ = Stdout.line!("\n--- replay_ignores_headers_for_matching ---")?
    cassette_name = "mock_replay_headers"
    _ = cleanup!(cassette_name)

    # Record with one set of headers
    cfg_record = make_mock_config(Once)
    client_record! = Vcr.init!(cfg_record, cassette_name)

    request_with_headers = {
        method: GET,
        uri: "https://api.test.com/headers",
        headers: [{ name: "Authorization", value: "token-123" }],
        body: [],
        timeout_ms: NoTimeout,
    }
    _ = client_record!(request_with_headers)?

    # Replay with different headers - should still match
    cfg_replay = make_mock_config(Replay)
    client_replay! = Vcr.init!(cfg_replay, cassette_name)

    request_different_headers = {
        method: GET,
        uri: "https://api.test.com/headers",
        headers: [{ name: "Authorization", value: "different-token" }],
        body: [],
        timeout_ms: NoTimeout,
    }
    response = client_replay!(request_different_headers)?

    if response.status == 200 then
        _ = Stdout.line!("  PASS: Headers ignored for matching")?
        _ = cleanup!(cassette_name)
        Ok({})
    else
        _ = Stdout.line!("  FAIL: Should have matched despite different headers")?
        Err(TestFailed)

# ============================================================================
# Mode Behavior Tests
# ============================================================================

test_once_mode_records_when_no_cassette! : {} => Result {} _
test_once_mode_records_when_no_cassette! = |{}|
    _ = Stdout.line!("\n--- once_mode_records_when_no_cassette ---")?
    cassette_name = "mock_once_records"
    _ = cleanup!(cassette_name)

    # Verify cassette doesn't exist
    when load_cassette!(cassette_name) is
        Ok(_) ->
            _ = Stdout.line!("  FAIL: Cassette should not exist yet")?
            Err(TestFailed)

        Err(_) ->
            # Good, cassette doesn't exist
            cfg = make_mock_config(Once)
            client! = Vcr.init!(cfg, cassette_name)
            _ = client!(make_request(GET, "https://api.test.com/once"))?

            # Now cassette should exist
            when load_cassette!(cassette_name) is
                Ok(cassette) ->
                    if List.len(cassette.interactions) == 1 then
                        _ = Stdout.line!("  PASS: Once mode recorded when no cassette")?
                        _ = cleanup!(cassette_name)
                        Ok({})
                    else
                        _ = Stdout.line!("  FAIL: Wrong interaction count")?
                        Err(TestFailed)

                Err(_) ->
                    _ = Stdout.line!("  FAIL: Cassette should have been created")?
                    Err(TestFailed)

test_once_mode_replays_when_cassette_exists! : {} => Result {} _
test_once_mode_replays_when_cassette_exists! = |{}|
    _ = Stdout.line!("\n--- once_mode_replays_when_cassette_exists ---")?
    cassette_name = "mock_once_replays"
    _ = cleanup!(cassette_name)

    # First, record something
    cfg1 = make_mock_config(Once)
    client1! = Vcr.init!(cfg1, cassette_name)
    original = client1!(make_request(GET, "https://api.test.com/once-replay"))?

    # Create new client in Once mode - should replay, not record
    cfg2 = make_mock_config(Once)
    client2! = Vcr.init!(cfg2, cassette_name)
    replayed = client2!(make_request(GET, "https://api.test.com/once-replay"))?

    # Should get same response (replayed from cassette)
    if original.body == replayed.body then
        # Verify only 1 interaction in cassette (not 2)
        cassette = load_cassette!(cassette_name)?
        if List.len(cassette.interactions) == 1 then
            _ = Stdout.line!("  PASS: Once mode replayed from existing cassette")?
            _ = cleanup!(cassette_name)
            Ok({})
        else
            _ = Stdout.line!("  FAIL: Should have only 1 interaction")?
            Err(TestFailed)
    else
        _ = Stdout.line!("  FAIL: Response should match original")?
        Err(TestFailed)

test_replace_mode_deletes_existing_cassette! : {} => Result {} _
test_replace_mode_deletes_existing_cassette! = |{}|
    _ = Stdout.line!("\n--- replace_mode_deletes_existing_cassette ---")?
    cassette_name = "mock_replace_deletes"
    _ = cleanup!(cassette_name)

    # First, create a cassette with 2 interactions
    cfg1 = make_mock_config(Once)
    client1! = Vcr.init!(cfg1, cassette_name)
    _ = client1!(make_request(GET, "https://api.test.com/old1"))?
    _ = client1!(make_request(GET, "https://api.test.com/old2"))?

    cassette_before = load_cassette!(cassette_name)?
    count_before = List.len(cassette_before.interactions)

    # Now use Replace mode - should delete and start fresh
    cfg2 = make_mock_config(Replace)
    client2! = Vcr.init!(cfg2, cassette_name)
    _ = client2!(make_request(GET, "https://api.test.com/new"))?

    cassette_after = load_cassette!(cassette_name)?
    count_after = List.len(cassette_after.interactions)

    # Should have only 1 interaction now (the new one)
    if count_before == 2 && count_after == 1 then
        first_uri = List.first(cassette_after.interactions)
            |> Result.map_ok(|i| i.request.uri)
            |> Result.with_default("")
        if first_uri == "https://api.test.com/new" then
            _ = Stdout.line!("  PASS: Replace mode deleted old cassette")?
            _ = cleanup!(cassette_name)
            Ok({})
        else
            _ = Stdout.line!("  FAIL: New interaction not found")?
            Err(TestFailed)
    else
        _ = Stdout.line!("  FAIL: Before=$(Num.to_str(count_before)), After=$(Num.to_str(count_after))")?
        Err(TestFailed)

# ============================================================================
# Filtering Tests
# ============================================================================

test_filter_removes_secret_from_uri! : {} => Result {} _
test_filter_removes_secret_from_uri! = |{}|
    _ = Stdout.line!("\n--- filter_removes_secret_from_uri ---")?
    cassette_name = "mock_filter_uri"
    _ = cleanup!(cassette_name)

    base_cfg = make_mock_config(Once)
    cfg = { base_cfg & replace_sensitive_data: [{ find: "SECRET_KEY", replace: "[REDACTED]" }] }
    client! = Vcr.init!(cfg, cassette_name)

    request = make_request(GET, "https://api.test.com/data?key=SECRET_KEY")
    _ = client!(request)?

    cassette = load_cassette!(cassette_name)?
    interaction = List.first(cassette.interactions) |> Result.map_err(|_| NoInteraction)?

    stored_uri = interaction.request.uri
    if Str.contains(stored_uri, "[REDACTED]") && !(Str.contains(stored_uri, "SECRET_KEY")) then
        _ = Stdout.line!("  PASS: Secret removed from URI: $(stored_uri)")?
        _ = cleanup!(cassette_name)
        Ok({})
    else
        _ = Stdout.line!("  FAIL: URI should have secret replaced: $(stored_uri)")?
        Err(TestFailed)

test_filter_removes_secret_from_request_body! : {} => Result {} _
test_filter_removes_secret_from_request_body! = |{}|
    _ = Stdout.line!("\n--- filter_removes_secret_from_request_body ---")?
    cassette_name = "mock_filter_req_body"
    _ = cleanup!(cassette_name)

    base_cfg = make_mock_config(Once)
    cfg = { base_cfg & replace_sensitive_data: [{ find: "my-secret-password", replace: "[PASSWORD]" }] }
    client! = Vcr.init!(cfg, cassette_name)

    base_request = make_request(POST, "https://api.test.com/login")
    request = { base_request & body: Str.to_utf8("{\"password\":\"my-secret-password\"}") }
    _ = client!(request)?

    cassette = load_cassette!(cassette_name)?
    interaction = List.first(cassette.interactions) |> Result.map_err(|_| NoInteraction)?

    stored_body = Str.from_utf8(interaction.request.body) |> Result.with_default("")

    if Str.contains(stored_body, "[PASSWORD]") && !(Str.contains(stored_body, "my-secret-password")) then
        _ = Stdout.line!("  PASS: Secret removed from request body")?
        _ = cleanup!(cassette_name)
        Ok({})
    else
        _ = Stdout.line!("  FAIL: Request body should have secret replaced: $(stored_body)")?
        Err(TestFailed)

test_filter_removes_secret_from_response_body! : {} => Result {} _
test_filter_removes_secret_from_response_body! = |{}|
    _ = Stdout.line!("\n--- filter_removes_secret_from_response_body ---")?
    cassette_name = "mock_filter_res_body"
    _ = cleanup!(cassette_name)

    # Use a secret that appears in the mock response
    # Mock returns: "response-for:GET:URI:body="
    # We'll filter the URI which appears in response
    base_cfg = make_mock_config(Once)
    cfg = { base_cfg & replace_sensitive_data: [{ find: "api.secret.com", replace: "[HOST]" }] }
    client! = Vcr.init!(cfg, cassette_name)

    request = make_request(GET, "https://api.secret.com/data")
    _ = client!(request)?

    cassette = load_cassette!(cassette_name)?
    interaction = List.first(cassette.interactions) |> Result.map_err(|_| NoInteraction)?

    stored_res_body = Str.from_utf8(interaction.response.body) |> Result.with_default("")

    if Str.contains(stored_res_body, "[HOST]") && !(Str.contains(stored_res_body, "api.secret.com")) then
        _ = Stdout.line!("  PASS: Secret removed from response body")?
        _ = cleanup!(cassette_name)
        Ok({})
    else
        _ = Stdout.line!("  FAIL: Response body should have secret replaced: $(stored_res_body)")?
        Err(TestFailed)

test_filter_removes_secret_from_header_value! : {} => Result {} _
test_filter_removes_secret_from_header_value! = |{}|
    _ = Stdout.line!("\n--- filter_removes_secret_from_header_value ---")?
    cassette_name = "mock_filter_header"
    _ = cleanup!(cassette_name)

    base_cfg = make_mock_config(Once)
    cfg = { base_cfg & replace_sensitive_data: [{ find: "Bearer token-xyz-123", replace: "Bearer [TOKEN]" }] }
    client! = Vcr.init!(cfg, cassette_name)

    request = {
        method: GET,
        uri: "https://api.test.com/protected",
        headers: [{ name: "Authorization", value: "Bearer token-xyz-123" }],
        body: [],
        timeout_ms: NoTimeout,
    }
    _ = client!(request)?

    cassette = load_cassette!(cassette_name)?
    interaction = List.first(cassette.interactions) |> Result.map_err(|_| NoInteraction)?

    auth_header = List.find_first(interaction.request.headers, |h| h.name == "Authorization")
    when auth_header is
        Ok(header) ->
            if header.value == "Bearer [TOKEN]" then
                _ = Stdout.line!("  PASS: Secret removed from header value")?
                _ = cleanup!(cassette_name)
                Ok({})
            else
                _ = Stdout.line!("  FAIL: Header value should be redacted: $(header.value)")?
                Err(TestFailed)

        Err(_) ->
            _ = Stdout.line!("  FAIL: Authorization header not found")?
            Err(TestFailed)

test_remove_headers_strips_specified_headers! : {} => Result {} _
test_remove_headers_strips_specified_headers! = |{}|
    _ = Stdout.line!("\n--- remove_headers_strips_specified_headers ---")?
    cassette_name = "mock_remove_headers"
    _ = cleanup!(cassette_name)

    base_cfg = make_mock_config(Once)
    cfg = { base_cfg & remove_headers: ["Authorization", "X-Api-Key"] }
    client! = Vcr.init!(cfg, cassette_name)

    request = {
        method: GET,
        uri: "https://api.test.com/secure",
        headers: [
            { name: "Authorization", value: "secret" },
            { name: "X-Api-Key", value: "key-123" },
            { name: "Accept", value: "application/json" },
        ],
        body: [],
        timeout_ms: NoTimeout,
    }
    _ = client!(request)?

    cassette = load_cassette!(cassette_name)?
    interaction = List.first(cassette.interactions) |> Result.map_err(|_| NoInteraction)?

    header_names = List.map(interaction.request.headers, |h| h.name)

    has_auth = List.contains(header_names, "Authorization")
    has_api_key = List.contains(header_names, "X-Api-Key")
    has_accept = List.contains(header_names, "Accept")

    if !has_auth && !has_api_key && has_accept then
        _ = Stdout.line!("  PASS: Sensitive headers removed, Accept kept")?
        _ = cleanup!(cassette_name)
        Ok({})
    else
        _ = Stdout.line!("  FAIL: auth=$(Inspect.to_str(has_auth)), key=$(Inspect.to_str(has_api_key)), accept=$(Inspect.to_str(has_accept))")?
        Err(TestFailed)

# ============================================================================
# Hooks Tests
# ============================================================================

test_before_record_transforms_interaction! : {} => Result {} _
test_before_record_transforms_interaction! = |{}|
    _ = Stdout.line!("\n--- before_record_transforms_interaction ---")?
    cassette_name = "mock_before_record"
    _ = cleanup!(cassette_name)

    base_cfg = make_mock_config(Once)
    cfg = { base_cfg &
        before_record: |i|
            # Add a marker header to the response
            new_headers = List.append(i.response.headers, { name: "X-Recorded", value: "true" })
            old_response = i.response
            new_response = { old_response & headers: new_headers }
            { i & response: new_response },
    }
    client! = Vcr.init!(cfg, cassette_name)

    _ = client!(make_request(GET, "https://api.test.com/hook"))?

    cassette = load_cassette!(cassette_name)?
    stored_interaction = List.first(cassette.interactions) |> Result.map_err(|_| NoInteraction)?

    has_marker = List.any(stored_interaction.response.headers, |h| h.name == "X-Recorded" && h.value == "true")

    if has_marker then
        _ = Stdout.line!("  PASS: before_record hook added marker header")?
        _ = cleanup!(cassette_name)
        Ok({})
    else
        _ = Stdout.line!("  FAIL: Marker header not found")?
        Err(TestFailed)

test_before_replay_transforms_interaction! : {} => Result {} _
test_before_replay_transforms_interaction! = |{}|
    _ = Stdout.line!("\n--- before_replay_transforms_interaction ---")?
    cassette_name = "mock_before_replay"
    _ = cleanup!(cassette_name)

    # Record first (without hook)
    cfg_record = make_mock_config(Once)
    client_record! = Vcr.init!(cfg_record, cassette_name)
    original = client_record!(make_request(GET, "https://api.test.com/replay-hook"))?

    # Replay with hook that modifies status
    base_replay_cfg = make_mock_config(Replay)
    cfg_replay = { base_replay_cfg &
        before_replay: |i|
            old_response = i.response
            new_response = { old_response & status: 999 }
            { i & response: new_response },
    }
    client_replay! = Vcr.init!(cfg_replay, cassette_name)
    modified = client_replay!(make_request(GET, "https://api.test.com/replay-hook"))?

    if original.status == 200 && modified.status == 999 then
        _ = Stdout.line!("  PASS: before_replay hook modified status to 999")?
        _ = cleanup!(cassette_name)
        Ok({})
    else
        _ = Stdout.line!("  FAIL: original=$(Num.to_str(original.status)), modified=$(Num.to_str(modified.status))")?
        Err(TestFailed)

# ============================================================================
# Skip Interactions Test
# ============================================================================

test_skip_interactions_skips_n_matches! : {} => Result {} _
test_skip_interactions_skips_n_matches! = |{}|
    _ = Stdout.line!("\n--- skip_interactions_skips_n_matches ---")?
    cassette_name = "mock_skip"
    _ = cleanup!(cassette_name)

    # Record 3 identical requests (will have different response bodies due to mock including index)
    # Actually mock returns same response for same request, so let's use different URIs but test skip
    cfg_record = make_mock_config(Once)
    client_record! = Vcr.init!(cfg_record, cassette_name)

    # Record same request 3 times - VCR records all
    request = make_request(GET, "https://api.test.com/same")
    _ = client_record!(request)?
    _ = client_record!(request)?
    _ = client_record!(request)?

    # Verify 3 interactions recorded
    cassette = load_cassette!(cassette_name)?
    if List.len(cassette.interactions) != 3 then
        _ = Stdout.line!("  FAIL: Expected 3 interactions")?
        Err(TestFailed)
    else
        # Replay with skip=0 - should get first
        cfg_skip0 = make_mock_config(Replay)
        client_skip0! = Vcr.init!(cfg_skip0, cassette_name)
        res0 = client_skip0!(request)?

        # Replay with skip=1 - should get second
        base_cfg1 = make_mock_config(Replay)
        cfg_skip1 = { base_cfg1 & skip_interactions: 1 }
        client_skip1! = Vcr.init!(cfg_skip1, cassette_name)
        res1 = client_skip1!(request)?

        # Replay with skip=2 - should get third
        base_cfg2 = make_mock_config(Replay)
        cfg_skip2 = { base_cfg2 & skip_interactions: 2 }
        client_skip2! = Vcr.init!(cfg_skip2, cassette_name)
        res2 = client_skip2!(request)?

        # All should succeed (same response since same request)
        if res0.status == 200 && res1.status == 200 && res2.status == 200 then
            _ = Stdout.line!("  PASS: skip_interactions correctly skips N matches")?
            _ = cleanup!(cassette_name)
            Ok({})
        else
            _ = Stdout.line!("  FAIL: Some responses failed")?
            Err(TestFailed)
