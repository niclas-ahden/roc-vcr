# roc-vcr

Record and replay HTTP interactions in your tests for speed and reliability.

VCR (Video Cassette Recorder) is a testing pattern where HTTP requests and responses are recorded to disk the first time they're made, then replayed in subsequent test runs. This makes your tests fast, deterministic, and independent of external services.

Inspired by Ruby's excellent [VCR gem](https://github.com/vcr/vcr). `roc-vcr` brings a similar approach to Roc.

View the full API documentation at [https://niclas-ahden.github.io/roc-vcr/](https://niclas-ahden.github.io/roc-vcr/).

## Why?

Testing code that makes HTTP requests is tricky:

- **Slow** - Every test run hits real APIs
- **Flaky** - Network issues cause random failures
- **Expensive** - Some APIs charge per request
- **Fragile** - External services change or go down

VCR solves this by recording real HTTP interactions once, then replaying them from disk. Your tests run in milliseconds and never fail due to network issues.

## Quick start

```roc
app [main!] {
    pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.20.0/X73hGh05nNTkDHU06FHC0YfFaQB1pimX7gncRcao5mU.tar.br",
    vcr: "package/main.roc",
}

import pf.Stdout
import pf.Http
import pf.File
import vcr.Vcr

main! = |_args|
    # Configure VCR (can be reused between tests)
    vcr_config = {
        mode: Once,
        cassette_dir: "cassettes",
        remove_headers: [],
        replace_sensitive_data: [],
        before_record: |interaction| interaction,
        before_replay: |interaction| interaction,
        skip_interactions: 0,
        http_send!: Http.send!,
        file_read!: File.read_bytes!,
        file_write!: File.write_bytes!,
        file_delete!: File.delete!,
    }

    # Create VCR client (one per test with a unique cassette name)
    client! = Vcr.init!(vcr_config, "my_test_cassette")

    request = {
        method: GET,
        uri: "https://api.example.com/data",
        headers: [],
        body: [],
        timeout_ms: NoTimeout,
    }

    # First run: makes real HTTP request and records it
    # Subsequent runs: replays from cassette file
    response = client!(request)?

    Stdout.line!("Status: $(Num.to_str(response.status))")
```

The cassette file `cassettes/my_test_cassette.json` now contains the recorded interaction. Commit it to version control and your tests will replay it forever.

See `examples/example.roc` for a complete working example.

## Configuration

| Field | Type | Description |
|-------|------|-------------|
| `mode` | `Mode` | Recording mode (`Once`, `Replay`, `Replace`) |
| `cassette_dir` | `Str` | Directory for cassette files |
| `remove_headers` | `List Str` | Headers to strip from recordings |
| `replace_sensitive_data` | `List { find, replace }` | Find/replace sensitive data |
| `before_record` | `Interaction -> Interaction` | Transform before recording |
| `before_replay` | `Interaction -> Interaction` | Transform before replaying |
| `skip_interactions` | `U64` | Number of interactions to skip when matching (useful when making duplicate requests and wanting to match a later one) |
| `http_send!` | `Request => Result Response err` | Pass `Http.send!` or equivalent from your platform |
| `file_read!` | `Str => Result (List U8) err` | Pass `File.read_bytes!` or equivalent from your platform |
| `file_write!` | `List U8, Str => Result {} err` | Pass `File.write_bytes!` or equivalent from your platform |
| `file_delete!` | `Str => Result {} err` | Pass `File.delete!` or equivalent from your platform |

## Modes

VCR has three modes:

**`Once`** - Record if cassette doesn't exist, replay otherwise (does not record new interactions in an existing cassette)
**`Replay`** - Only replay from cassette, crash if cassette or interaction not found
**`Replace`** - Delete cassette and record fresh interactions

Why no `Record`? People seem to disagree on what `Record` means (is it the equivalent of `Replace`? or `Once`? or does it always record all new interactions without replacing old ones?) We chose the names above to try and make the API more obvious.

## Filtering sensitive data

Keep passwords, private information etc. out of your cassettes:

```roc
vcr_config = {
    # [...]
    replace_sensitive_data: [
        { find: "4E4A7UDI6F", replace: "<API_KEY>" },
        { find: "hunter2", replace: "<PASSWORD>" },
    ],
    remove_headers: ["Authorization", "Cookie"],
}
```

Secrets are filtered from:
- Request and response bodies
- Request URIs
- Header values

The cassette stores placeholders like `<API_KEY>` and matches against those too when replaying.

Use `before_record` and `before_replay` to filter more complex or dynamic data (e.g. filtering specific query parameters or a generated secret).

## Hooks

Transform interactions before recording or replaying.

**Type signature:** `Vcr.Interaction -> Vcr.Interaction`

```roc
vcr_config = {
    [...]
    before_record: your_custom_function,
    before_replay: |i| i,  # Identity function - no transformation (default)
}
```

**Execution order:**
- Recording: `HTTP Response -> before_record hook -> filters -> save to cassette`
- Replaying: `Load from cassette -> before_replay hook -> return response`

## How request matching works

VCR matches requests based on:
- HTTP method (GET, POST, etc.)
- Full URI (including query parameters)
- Body content (hashed with FNV-1a)

Two requests match if all three are identical. The first matching interaction in the cassette is returned.

**Note:** Headers are not used for matching. Requests with different headers but identical method, URI, and body will match.

## Sequential matching with `skip_interactions`

Sometimes your test makes multiple requests that would all match the same interaction in the cassette. For example, checking an initial value, updating it, then verifying the update. Use `skip_interactions` to skip past earlier interactions and match later ones.

```roc
# Initial request - matches first interaction
initial_value = api_get!(client, "resource/123")

# Update the resource
api_update!(client, "resource/123", { value: 42 })

# Verify the update - skip the first 2 interactions (GET, POST)
# to match the 3rd interaction (the second GET with updated data)
verify_config = { vcr_config & skip_interactions: 2 }
verify_client! = Vcr.init!(verify_config, "same_cassette")
updated_value = api_get!(verify_client!, "resource/123")
```

**How it works:**
- `skip_interactions: N` skips the first N interactions in the cassette
- Then finds the first match in the remaining interactions
- Useful when sequential requests would match the same interaction

## We crash!

We want the API of `roc-vcr` to line up with the `Http` module in `basic-cli` and `basic-webserver` so that it's a drop-in replacement. There are several ways to achieve this and for now we've chosen to use `crash` when there's a VCR-related error (such as a missing interaction in `Replay` mode, decode errors, or save failures) so that we don't have to introduce new error types. This works fine as `roc-vcr` should only be used in tests and crashing gives clear error messages.

## Contributing

We're open for PRs! Run all `roc-vcr`'s tests like so:

```bash
./tests.sh
```

Or run individual suites:

```bash
roc run test/VcrMockTest.roc        # Mock tests (fast, no network)
roc run test/VcrIntegrationTest.roc # Integration tests (requires network)
./test/crash/run_crash_tests.sh     # Crash scenario tests
```

## Status

`roc-vcr` is early but functional. The API will change as Roc evolves. If you're familiar with VCR in other languages, you'll feel right at home.

## Documentation

View the full API documentation at [https://niclas-ahden.github.io/roc-vcr/](https://niclas-ahden.github.io/roc-vcr/).

### Generating documentation locally

To generate documentation for a specific version:

```bash
./docs.sh 0.1.0
```

This will:
1. Generate HTML documentation from the Roc module.
2. Place it in `www/0.1.0/`.
3. You can then open `www/0.1.0/index.html` in your browser.

### Publishing documentation

Documentation is automatically deployed to GitHub Pages when triggered manually:

1. Generate the docs locally using `./docs.sh VERSION`.
2. Commit and push the changes to `www/`.
3. Go to the GitHub Actions tab in the repository.
4. Run the "Deploy static content to Pages" workflow manually.
5. Your docs will be published at `https://niclas-ahden.github.io/roc-vcr/VERSION/`.
