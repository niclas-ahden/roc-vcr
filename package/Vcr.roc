## Record and replay HTTP interactions in your tests for speed and reliability.
##
## VCR (Video Cassette Recorder) is a testing pattern where HTTP requests and responses are recorded to disk the first time they're made, then replayed in subsequent test runs. This makes your tests fast, deterministic, and independent of external services.
##
## Inspired by Ruby's excellent [VCR gem](https://github.com/vcr/vcr). `roc-vcr` brings a similar approach to Roc.
module [
    Cassette,
    Interaction,
    Mode,
    Config,
    Request,
    Response,
    Timeout,
    StoredCassette,
    StoredInteraction,
    StoredRequest,
    init!,
]

import json.Json

## Recording mode that determines VCR behavior.
## - `Once`: Record if cassette doesn't exist, replay otherwise (does not record new interactions in an existing cassette)
## - `Replay`: Only replay from cassette, crash if cassette or interaction not found
## - `Replace`: Delete cassette and record fresh interactions
Mode : [
    Replay,
    Once,
    Replace,
]

## HTTP method. Matches the `Method` type from `basic-cli`.
Method : [GET, POST, PUT, DELETE, HEAD, OPTIONS, PATCH, CONNECT, TRACE, EXTENSION Str]

## HTTP header as a name-value pair.
Header : { name : Str, value : Str }

## Request timeout configuration. Matches `basic-cli`.
Timeout : [NoTimeout, TimeoutMilliseconds U64]

## HTTP request. Matches `basic-cli` exactly so you can pass `Http.send!` directly.
Request : {
    method : Method,
    uri : Str,
    headers : List Header,
    body : List U8,
    timeout_ms : Timeout,
}

## HTTP response. Compatible with `basic-cli`.
Response : {
    status : U16,
    headers : List Header,
    body : List U8,
}

## A single HTTP interaction: one request paired with its response.
Interaction : {
    request : Request,
    response : Response,
}

## A cassette containing recorded HTTP interactions. Named after VHS cassette tapes.
Cassette : {
    name : Str,
    interactions : List Interaction,
}

## Request as stored in cassette JSON. Method is a string, timeout is omitted.
## Useful if you need to decode cassette files directly.
StoredRequest : {
    method : Str,
    uri : Str,
    headers : List Header,
    body : List U8,
}

## Interaction as stored in cassette JSON.
StoredInteraction : {
    request : StoredRequest,
    response : Response,
}

## Cassette as stored in JSON files. Use with `roc-json` to decode cassettes directly.
StoredCassette : {
    name : Str,
    interactions : List StoredInteraction,
}

## Convert Request to StoredRequest (drop timeout_ms, stringify method)
request_to_stored : Request -> StoredRequest
request_to_stored = |req| {
    method: method_to_str(req.method),
    uri: req.uri,
    headers: req.headers,
    body: req.body,
}

## Convert StoredRequest to Request (add default timeout_ms, parse method)
stored_to_request : StoredRequest -> Request
stored_to_request = |stored|
    method =
        when stored.method is
            "GET" -> GET
            "POST" -> POST
            "PUT" -> PUT
            "DELETE" -> DELETE
            "HEAD" -> HEAD
            "OPTIONS" -> OPTIONS
            "PATCH" -> PATCH
            "CONNECT" -> CONNECT
            "TRACE" -> TRACE
            other -> EXTENSION(other)
    {
        method,
        uri: stored.uri,
        headers: stored.headers,
        body: stored.body,
        timeout_ms: NoTimeout,
    }

## Convert Interaction to StoredInteraction
interaction_to_stored : Interaction -> StoredInteraction
interaction_to_stored = |interaction| {
    request: request_to_stored(interaction.request),
    response: interaction.response,
}

## Convert StoredInteraction to Interaction
stored_to_interaction : StoredInteraction -> Interaction
stored_to_interaction = |stored| {
    request: stored_to_request(stored.request),
    response: stored.response,
}

## Convert Cassette to StoredCassette
cassette_to_stored : Cassette -> StoredCassette
cassette_to_stored = |cassette| {
    name: cassette.name,
    interactions: List.map(cassette.interactions, interaction_to_stored),
}

## Convert StoredCassette to Cassette
stored_to_cassette : StoredCassette -> Cassette
stored_to_cassette = |stored| {
    name: stored.name,
    interactions: List.map(stored.interactions, stored_to_interaction),
}

## VCR configuration.
##
## - `mode`: Recording mode (`Once`, `Replay`, `Replace`)
## - `cassette_dir`: Directory for cassette files
## - `remove_headers`: Headers to strip from recordings
## - `replace_sensitive_data`: Find/replace sensitive data
## - `before_record`: Transform before recording
## - `before_replay`: Transform before replaying
## - `skip_interactions`: Number of interactions to skip when matching (useful when making duplicate requests and wanting to match a later one)
## - `http_send!`: Pass `Http.send!` or equivalent from your platform
## - `file_read!`: Pass `File.read_bytes!` or equivalent from your platform
## - `file_write!`: Pass `File.write_bytes!` or equivalent from your platform
## - `file_delete!`: Pass `File.delete!` or equivalent from your platform
Config err file_err : {
    mode : Mode,
    cassette_dir : Str,
    remove_headers : List Str,
    replace_sensitive_data : List { find : Str, replace : Str },
    before_record : Interaction -> Interaction,
    before_replay : Interaction -> Interaction,
    skip_interactions : U64,
    http_send! : Request => Result Response err,
    file_read! : Str => Result (List U8) file_err,
    file_write! : List U8, Str => Result {} file_err,
    file_delete! : Str => Result {} file_err,
}

## Convert HTTP method tag to string for request key
method_to_str : Method -> Str
method_to_str = |method|
    when method is
        GET -> "GET"
        POST -> "POST"
        PUT -> "PUT"
        DELETE -> "DELETE"
        HEAD -> "HEAD"
        OPTIONS -> "OPTIONS"
        PATCH -> "PATCH"
        CONNECT -> "CONNECT"
        TRACE -> "TRACE"
        EXTENSION(name) -> "EXTENSION(${name})"

## FNV-1a hash algorithm for request body matching
hash_bytes : List U8 -> U64
hash_bytes = |bytes|
    fnv_offset_basis = 0xcbf29ce484222325
    fnv_prime = 0x100000001b3
    List.walk(
        bytes,
        fnv_offset_basis,
        |hash, byte|
            Num.bitwise_xor(hash, Num.to_u64(byte))
            |> Num.mul_wrap(fnv_prime),
    )

## Remove specific headers from a header list (case-insensitive)
remove_headers_from_list : List Header, List Str -> List Header
remove_headers_from_list = |headers, names_to_remove|
    List.keep_if(
        headers,
        |header|
            lowercase_name = Str.with_ascii_lowercased(header.name)
            !(
                List.any(
                    names_to_remove,
                    |remove_name|
                        Str.with_ascii_lowercased(remove_name) == lowercase_name,
                )
            ),
    )

## Replace secrets in header values
filter_header_values : List Header, List { find : Str, replace : Str } -> List Header
filter_header_values = |headers, replacements|
    List.map(
        headers,
        |header|
            filtered_value = List.walk(
                replacements,
                header.value,
                |acc, { find, replace }| Str.replace_each(acc, find, replace),
            )
            { header & value: filtered_value },
    )

## Replace all sensitive data in bytes
replace_all_in_bytes : List U8, List { find : Str, replace : Str } -> List U8
replace_all_in_bytes = |bytes, replacements|
    when Str.from_utf8(bytes) is
        Ok(str) ->
            filtered_str = List.walk(
                replacements,
                str,
                |acc, { find, replace }| Str.replace_each(acc, find, replace),
            )
            Str.to_utf8(filtered_str)

        Err(_) -> bytes

## Apply all configured filters to an interaction
apply_filters : Interaction, { remove_headers : List Str, replace_sensitive_data : List { find : Str, replace : Str } } -> Interaction
apply_filters = |interaction, filter_config|
    req = interaction.request
    res = interaction.response

    # Filter request headers
    req_headers_removed = remove_headers_from_list(req.headers, filter_config.remove_headers)
    req_headers_filtered = filter_header_values(req_headers_removed, filter_config.replace_sensitive_data)

    # Filter response headers
    res_headers_removed = remove_headers_from_list(res.headers, filter_config.remove_headers)
    res_headers_filtered = filter_header_values(res_headers_removed, filter_config.replace_sensitive_data)

    # Filter bodies
    filtered_req_body = replace_all_in_bytes(req.body, filter_config.replace_sensitive_data)
    filtered_res_body = replace_all_in_bytes(res.body, filter_config.replace_sensitive_data)

    # Filter URI
    filtered_uri = List.walk(
        filter_config.replace_sensitive_data,
        req.uri,
        |uri, { find, replace }| Str.replace_each(uri, find, replace),
    )

    filtered_req = { req &
        uri: filtered_uri,
        headers: req_headers_filtered,
        body: filtered_req_body,
    }

    filtered_res = { res &
        headers: res_headers_filtered,
        body: filtered_res_body,
    }

    { request: filtered_req, response: filtered_res }

## Create a request key for matching (method + URI + body hash)
request_key : Request -> Str
request_key = |req|
    method_str = method_to_str(req.method)
    body_hash = hash_bytes(req.body) |> Num.to_str
    "${method_str}:${req.uri}:${body_hash}"

## Find a matching interaction in the cassette
find_interaction : List Interaction, Str, U64 -> Result Interaction [NotFound]
find_interaction = |interactions, key, skip_count|
    remaining = List.drop_first(interactions, skip_count)
    List.find_first(
        remaining,
        |interaction|
            request_key(interaction.request) == key,
    )
    |> Result.map_err(|_| NotFound)

## Load cassette from file (decodes StoredCassette, converts to Cassette)
load_cassette! : (Str => Result (List U8) file_err), Str, Str => Result Cassette [FileNotFound] where file_err implements Inspect
load_cassette! = |file_read!, cassette_dir, cassette_name|
    path = "${cassette_dir}/${cassette_name}.json"
    when file_read!(path) is
        Ok(bytes) ->
            decoded : Result StoredCassette _
            decoded = Decode.from_bytes(bytes, Json.utf8_with({ skip_missing_properties: Bool.true }))
            when decoded is
                Ok(stored) -> Ok(stored_to_cassette(stored))
                Err(err) ->
                    crash "VCR: Failed to decode cassette ${cassette_name}: ${Inspect.to_str(err)}"

        Err(_) -> Err(FileNotFound)

## Save cassette to file (converts Cassette to StoredCassette, then encodes)
save_cassette! : (List U8, Str => Result {} file_err), Str, Cassette => Result {} [SaveError Str] where file_err implements Inspect
save_cassette! = |file_write!, cassette_dir, cassette|
    path = "${cassette_dir}/${cassette.name}.json"
    stored = cassette_to_stored(cassette)
    json_bytes = Encode.to_bytes(stored, Json.utf8_with({ skip_missing_properties: Bool.true }))
    when file_write!(json_bytes, path) is
        Ok({}) -> Ok({})
        Err(err) ->
            crash "VCR: Failed to save cassette ${cassette.name}: ${Inspect.to_str(err)}"

## Create a VCR client for a specific cassette. Returns a function that works like `Http.send!`.
##
## ```roc
## client! = Vcr.init!(config, "my_api_test")
## response = client!(request)?  # Records or replays based on mode
## ```
##
## The returned client handles recording and replay automatically based on the config mode.
## Crashes with a descriptive message on VCR errors (decode failures, missing interactions in Replay mode, etc.).
init! : Config err file_err, Str => (Request => Result Response err) where file_err implements Inspect
init! = |cfg, cassette_name|
    file_read! = cfg.file_read!
    file_write! = cfg.file_write!
    file_delete! = cfg.file_delete!
    http_send! = cfg.http_send!
    cassette_dir = cfg.cassette_dir

    # Determine recording mode at init time
    should_record =
        when cfg.mode is
            Replace ->
                # Only delete if cassette exists - avoids crash on first run
                when load_cassette!(file_read!, cassette_dir, cassette_name) is
                    Ok(_) ->
                        # File exists, delete it
                        path = "${cassette_dir}/${cassette_name}.json"
                        when file_delete!(path) is
                            Ok({}) -> {}
                            Err(err) -> crash "VCR: Failed to delete cassette ${cassette_name}: ${Inspect.to_str(err)}"

                    Err(FileNotFound) ->
                        # File doesn't exist, nothing to delete
                        {}
                Bool.true

            Once ->
                when load_cassette!(file_read!, cassette_dir, cassette_name) is
                    Ok(_) -> Bool.false
                    Err(_) -> Bool.true

            Replay ->
                Bool.false

    # Return the effectful request handler function
    |request|
        # Load cassette from storage (or create empty one)
        cassette =
            when load_cassette!(file_read!, cassette_dir, cassette_name) is
                Ok(c) -> c
                Err(FileNotFound) -> { name: cassette_name, interactions: [] }

        if should_record then
            # Recording mode: make real request and save to cassette
            when http_send!(request) is
                Ok(response) ->
                    # Apply before_record hook
                    hooked = cfg.before_record({ request, response })

                    # Apply filters
                    filtered = apply_filters(
                        hooked,
                        { remove_headers: cfg.remove_headers, replace_sensitive_data: cfg.replace_sensitive_data },
                    )

                    # Add to cassette and save
                    new_cassette = { cassette &
                        interactions: List.append(cassette.interactions, filtered),
                    }

                    _ = save_cassette!(file_write!, cassette_dir, new_cassette)
                    Ok(response)

                Err(err) -> Err(err)
        else
            # Replay mode: find matching interaction in cassette
            # Apply filters to request for key matching
            filtered = apply_filters(
                { request, response: { status: 0, headers: [], body: [] } },
                { remove_headers: cfg.remove_headers, replace_sensitive_data: cfg.replace_sensitive_data },
            )

            key = request_key(filtered.request)

            when find_interaction(cassette.interactions, key, cfg.skip_interactions) is
                Ok(interaction) ->
                    # Apply before_replay hook
                    replayed = cfg.before_replay(interaction)
                    Ok(replayed.response)

                Err(NotFound) ->
                    skip_info = if cfg.skip_interactions > 0 then " (skip_interactions: ${Num.to_str(cfg.skip_interactions)})" else ""
                    crash "VCR Replay mode: No matching interaction found for ${key}${skip_info}"
