# roc-vcr

Record and replay HTTP interactions in your tests for speed and reliability.

VCR (Video Cassette Recorder) is a testing pattern where HTTP requests and responses are recorded to disk the first time they're made, then replayed in subsequent test runs. This makes your tests fast, deterministic, and independent of external services.

Inspired by Ruby's excellent [VCR gem](https://github.com/vcr/vcr). `roc-vcr` brings a similar approach to Roc.

## Why?

Testing code that makes HTTP requests is tricky:

- **Slow** - Every test run hits real APIs
- **Flaky** - Network issues cause random failures
- **Expensive** - Some APIs charge per request
- **Fragile** - External services change or go down

VCR solves this by recording real HTTP interactions once, then replaying them from disk. Your tests run in milliseconds and never fail due to network issues.

## Quick start

Write the code that talks to an API so that it takes its HTTP function as an argument. It needs nothing from `roc-vcr`:

```roc
## Invoices.roc
import http.Request

Invoices :: [].{
	Invoice : { id : Str, amount : U64, paid : Bool }

	get! = |send!, token, id| {
		request = Request.from_method(GET)
			.with_uri("https://api.example.com/invoices/${id}")
			.add_header("Authorization", "Bearer ${token}")
		response = send!(request)?
		invoice : Try(Invoice, _)
		invoice = Json.parse(Str.from_utf8_lossy(response.body()))
		invoice
	}
}
```

Your app passes it basic-cli's `Http.send!`, as in `Invoices.get!(Http.send!, token, "42")`. A test passes a VCR client instead, which has the same type:

```roc
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.26.0/EuuihZ91yAY1ANck1QytRBcW2jexEfH6yVmxcPCHEHDz.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/2.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	vcr: "https://github.com/niclas-ahden/roc-vcr/releases/download/0.1.0/_ZYAPfxP9sxBnqjLWeNWv0jiASRunEGPpkcH3UStOT8.tar.br",
}

import pf.Env
import pf.Http
import pf.OsStr
import pf.Path
import vcr.Vcr
import Invoices

main! : List(OsStr) => Try({}, _)
main! = |_args| {
	# Replay by default, `VCR_MODE=once` or `VCR_MODE=replace` to record
	mode = Vcr.parse_mode(Env.var_str!(OsStr.from_str("VCR_MODE")) ?? "replay")?
	# Only recording sends the token. A replay never sends a request.
	token = Env.var_str!(OsStr.from_str("API_TOKEN")) ?? "unused"

	client! = Vcr.init!({ cassette_dir: Path.utf8("tests/cassettes"), http_send!: Http.send!, mode }, "invoice")?
	invoice = Invoices.get!(client!, token, "42")?

	if invoice.amount == 1200 Ok({}) else Err(WrongAmount(invoice.amount))
}
```

Run it once with `VCR_MODE=once` and a real token, and the request is sent and recorded in `tests/cassettes/invoice.json`. The token is not in that file, see [Keeping secrets out](#keeping-secrets-out-of-cassettes). Commit it, and every later run replays it without touching the network.

The client has the type of `http_send!`: it takes and returns the `Request` and `Response` of [roc-lang/http](https://github.com/roc-lang/http), as basic-cli's `Http.send!` does. That is why your code can take either one.

See `examples/example.roc` for a complete working example that replays from a committed cassette.

Release 0.1.0 is a bundle for the old Roc compiler. Until the next release, depend on a checkout of this repository by path (`vcr: "../roc-vcr/package/main.roc"`) to use it with the current compiler.

## Configuration

Only `cassette_dir` and `http_send!` are required. Every other field has a default, so a config written inline at the `Vcr.init!` call names only what it changes. A config bound to a name first needs a `Vcr.Config(_, _)` annotation for the defaults to apply:

```roc
config : Vcr.Config(_, _)
config = { cassette_dir: Path.utf8("tests/cassettes"), http_send!: Http.send!, mode: Replay }

client! = Vcr.init!(config, "create_invoice")?
signed! = Vcr.init!({ ..config, redact: ["signature"] }, "sign_invoice")?
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `cassette_dir` | your platform's path | required | Where the cassettes are, e.g. `Path.utf8("tests/cassettes")`. Created on the first recording |
| `http_send!` | `Request => Try(Response, err)` | required | Sends a request for real while recording, e.g. basic-cli's `Http.send!` |
| `mode` | `Mode` | `Replay` | `Replay`, `Once` or `Replace`, see [Modes](#modes) |
| `redact` | `List(Str)` | `[]` | More names whose values are kept out of the cassette, see [Keeping secrets out](#keeping-secrets-out-of-cassettes) |
| `keep` | `List(Str)` | `[]` | Names that end like a secret but hold none, whose values stay in the cassette, see [Tokens that page](#tokens-that-page) |
| `remove_headers` | `List(Str)` | `[]` | Headers to leave out of the cassette, in any case |
| `replace_sensitive_data` | `List({ find : Str, replace : Str })` | `[]` | Exact text to replace |
| `filter_request` | `Request -> Request` | no change | Your own change to every request |
| `filter_response` | `Response -> Response` | no change | Your own change to every recorded response |
| `match_headers` | `List(Str)` | `[]` | Request headers that have to match too, in any case, see [How request matching works](#how-request-matching-works) |

## Modes

- **`Replay`** (the default) - Only replay from the cassette, and never send a request. A missing cassette or interaction is an error
- **`Once`** - Record if the cassette doesn't exist, replay otherwise. It never adds to an existing cassette
- **`Replace`** - Delete the cassette and record every request into a new one

Read the mode from an environment variable, as the quick start does, and you re-record a test without editing it:

```bash
VCR_MODE=replace ./tests.roc create_invoice
```

`Vcr.parse_mode` takes the name in any case. The default stays `Replay`, so a test run in CI never reaches the network, and a missing recording fails loudly instead of being made there.

Why no `Record`? People seem to disagree on what `Record` means (is it the equivalent of `Replace`? or `Once`? or does it always record all new interactions without replacing old ones?) We chose the names above to try and make the API more obvious.

## One client per cassette

A client settles its mode when `Vcr.init!` creates it. That is when `Replace` deletes the old cassette, when `Once` decides whether to record, and when a replay reads the cassette. So give every cassette exactly one client. A client never sees what another client does to its cassette.

A replay answers a request with the first recording that matches it, so a request sent again gets the same answer. When a test expects a new answer to the same request, say it reads an invoice, pays it and reads it again, record the part after the change into a cassette of its own:

```roc
client! = Vcr.init!(config, "pay_invoice")?
unpaid = Invoices.get!(client!, token, "42")?
Invoices.pay!(client!, token, "42")?

after_paying! = Vcr.init!(config, "pay_invoice_after")?
paid = Invoices.get!(after_paying!, token, "42")?
```

The second client can be created at any point, since it has a cassette to itself.

When your code repeats a request by itself, as when it polls a job until it is done, a replay gives it the first recorded answer every time. A client cannot count the requests it has answered, since a Roc function keeps no state between calls, so a test of such code needs a fake `http_send!` of its own instead.

## Keeping secrets out of cassettes

Cassettes are committed, so tokens, passwords and cookies have to stay out of them. These never reach a cassette, with no config needed:

- the credentials of `Authorization` and `Proxy-Authorization`, which keep their scheme: `Bearer <CREDENTIALS>`
- the values in `Cookie` and `Set-Cookie`, which keep the name of every cookie and the attributes: `session=<SESSION>; Path=/; HttpOnly`
- the user and password of a URL: `postgres://<CREDENTIALS>@db/app`
- the token after `Bearer`, wherever it is
- the value of every name that ends in `token`, `secret`, `password`, `passwd`, `pwd`, `api_key`, `private_key`, `access_key` or `secret_key`, except a [token that pages](#tokens-that-page)

A name is found in any case and with or without `_` and `-`, so `access_token`, `Access-Token` and `accessToken` are one name. It is found as a header, a query or form parameter (`access_token=...`), a JSON field (`"access_token": "..."`), a JSON field inside a JSON string, and a `name: value` line. The value becomes the name in upper case: `access_token=<ACCESS_TOKEN>`. A JSON number becomes that text in quotes, so the JSON stays valid. Booleans are left, since a flag like `"has_password": true` holds no secret and has to decode as a Boolean on replay. Nulls, objects and lists are left too, and the names inside them are looked at on their own.

Because it goes by the name and not the value, this also catches values you don't know when the test starts, like a token the API hands back in one response and your code sends in the next, or a signature computed from a secret. It catches them in response bodies too, for example inside a paging URL. And since a replayed request is scrubbed the same way before it is matched, a replay matches whatever the value is, so the test replays without real credentials.

### Tokens that page

Some names end in `token` without holding a secret. A token that says where the next page of results starts is one, and it has to stay: hidden, the requests for every page after the first look the same, and a replay answers all of them with the second page. So a name that ends in `token` and has `page`, `next`, `continuation`, `sync` or `cursor` in it stays, as `pageToken`, `nextPageToken`, `NextToken`, `continuationToken` and `syncToken` do.

For a name that pages under another word, put it in `keep`, found the same way as the built-in names:

```roc
client! = Vcr.init!({ cassette_dir: Path.utf8("tests/cassettes"), http_send!: Http.send!, keep: ["resume_token"] }, "changes")?
```

`keep` only leaves names that end like a secret. Credentials, cookies, URL passwords and the token after `Bearer` are kept out whatever it says, and so is a name that is in `redact` as well.

### Keeping out more

Three fields of the config add to the built-in rules:

```roc
client! = Vcr.init!(
	{
		cassette_dir: Path.utf8("tests/cassettes"),
		http_send!: Http.send!,
		redact: ["appsecret_proof"],
		remove_headers: ["X-Request-Id"],
		replace_sensitive_data: [{ find: account_id, replace: "<ACCOUNT_ID>" }],
	},
	"insights",
)?
```

- **`redact`** adds names, found the same way as the built-in ones.
- **`remove_headers`** leaves headers out entirely. A removed header is gone from both sides of a match, so naming it in `match_headers` as well has no effect.
- **`replace_sensitive_data`** replaces exact text, for a secret with no name to find it by.

For anything else, `filter_request` and `filter_response` take your own function. A request is filtered on its way into the cassette and again before it is matched against it, so a request changed when it was recorded still matches when it is replayed. A response is filtered only when it is recorded. The response handed back while recording is always the real one.

The order is: your `filter_request` or `filter_response`, then `remove_headers`, the scrubbing above, and `replace_sensitive_data`. A body that is not UTF-8 is not searched.

## How request matching works

VCR matches requests based on:
- HTTP method (GET, POST, etc.)
- Full URI (including query parameters)
- Body content
- The headers named in `match_headers`, if any

All of them are compared after filtering. The first matching interaction in the cassette is returned. Other headers are not used for matching.

When a header decides what the server answers, like an API version, name it in `match_headers`, in any case:

```roc
client! = Vcr.init!({ ..config, match_headers: ["Api-Version"] }, "invoice_v2")?
```

A header has to have the same values in the recording and the request, and a header that is missing on one side and not on the other is a difference. Since values are compared after filtering, a scrubbed header only matches on what is left of it. `Authorization` compares its scheme, as in `Bearer <CREDENTIALS>`, and never the credentials, so a replay still works without them. The headers a platform adds while sending, like `Host` or `Content-Length`, are not part of the request and never match.

When part of a request changes on every run, like a timestamp or a nonce, remove it in `filter_request` and it no longer affects matching:

```roc
without_timestamp = |request|
	match request.uri().split_first("&ts=") {
		Ok({ before, after: _ }) => request.with_uri(before)
		Err(_) => request
	}
```

When nothing matches, the error names the closest recording, how it differs, and how to record the request:

```
No recorded interaction in tests/cassettes/invoice.json matches POST https://api.example.com/invoice with a 58 byte body. It has POST https://api.example.com/invoice with a 58 byte body, whose body differs from byte 46: recorded "amount\":100,\"rows\":[]}", sent "amount\":101,\"rows\":[]}". Run in Replace mode to record the cassette again.
```

## Errors

Every error carries a message that names the cassette file.

`Vcr.init!` returns a `Try`, and fails when it cannot settle the cassette:

| Error | When |
|-------|------|
| `CassetteNotFound(Str)` | `Replay` mode and there is no cassette file |
| `CassetteReadFailed(Str)` | The cassette file is there but could not be read |
| `CassetteDecodeFailed(Str)` | The cassette file is not valid cassette JSON |
| `CassetteDeleteFailed(Str)` | `Replace` mode and the old cassette could not be deleted |

So a missing or broken cassette fails the test where the client is made, with `?`. The code under test never sees the error, so it cannot retry it, log it and carry on, or turn it into a vaguer one of its own.

The client has the same type as a platform's `send!`. When VCR fails while answering a request, the client returns one of these tags next to whatever errors `http_send!` has:

| Error | When |
|-------|------|
| `InteractionNotFound(Str)` | No recorded interaction matches the request |
| `CassetteSaveFailed(Str)` | The cassette could not be written |
| `CassetteReadFailed(Str)` | A client that records could not read the cassette it adds to |
| `CassetteDecodeFailed(Str)` | A client that records found a cassette that is not valid cassette JSON |

These reach the test through the code under test, so if that code handles errors without passing them on, check how it reports them.

The tags join the error type of `http_send!`, which therefore has to be an open tag union. An inferred type, `_`, and the return type of a platform function like `Http.send!` are open. If you annotate one yourself, end the union with `..`, as in `Try(Response, [MyHttpError, ..])`.

## Cassette files

A cassette is one JSON file, `<cassette_dir>/<cassette name>.json`, with one field per line so a new recording reads well in a diff:

```json
{
  "name": "invoice",
  "interactions": [
    {
      "request": {
        "method": "GET",
        "uri": "https://api.example.com/invoices/42",
        "headers": [
          { "name": "Authorization", "value": "Bearer <CREDENTIALS>" }
        ],
        "body": ""
      },
      "response": {
        "status": 200,
        "headers": [
          { "name": "content-type", "value": "application/json" }
        ],
        "body": "{\"id\":\"42\",\"amount\":1200,\"paid\":false}"
      }
    }
  ]
}
```

A body is stored as text when it is UTF-8, which is what JSON, HTML and form bodies are. Anything else, like an image, is stored as base64 in `body_base64` instead, and replays byte for byte. The timeout of a request is not stored.

A client that replays reads its cassette once, when it is created, however many requests it answers. It scrubs the recorded requests the way it scrubs the ones it gets, so a cassette recorded before a name was added to `redact`, `remove_headers` or `replace_sensitive_data`, or by a version that kept out less, still matches. Your own `filter_request` only runs on the requests a client gets, so a cassette recorded before you added one needs recording again.

Cassettes recorded with `roc-vcr` 0.1.0, which stored bodies as lists of bytes, still replay. A cassette recorded again is written in the current format.

To read a cassette in your own code, use `Vcr.decode_cassette`, and `Vcr.encode_cassette` to write one.

## Other platforms

`http_send!` and the client take and return the `Request` and `Response` of [roc-lang/http](https://github.com/roc-lang/http), which is what basic-cli's `Http.send!` does. A platform with its own types needs a function that converts them.

`cassette_dir` can be any value with the methods in `Vcr.CassetteDir`: `join`, `display`, `exists!`, `read_bytes!`, `write_bytes!`, `delete!` and `create_all!`. basic-cli's `Path` has all of them. On a platform whose path type differs, wrap it in a type of your own that has them. `tests/FailingDir.roc` is an example.

## Upgrading from 0.1.0

- The client takes and returns roc-lang/http's `Request` and `Response`, the types of basic-cli's `Http.send!`. Build requests with `Request.from_method(GET).with_uri(...)` and read responses with `.status()`, `.headers()` and `.body()`. `Vcr.Request`, `Vcr.Response`, `Vcr.Method`, `Vcr.Header` and `Vcr.Timeout` are gone.
- Code that took a record-based HTTP function can now take `Http.send!` as it is, so an adapter around it can go.
- `Vcr.init!` returns a `Try`: `client! = Vcr.init!(config, "name")?`. A missing, unreadable or broken cassette is an error from `init!` instead of a crash.
- `skip_interactions` is gone. Give the part of a test that expects a new answer to the same request a cassette of its own, see [One client per cassette](#one-client-per-cassette).
- The config has defaults now. Remove `before_record: |interaction| interaction`, `before_replay: |interaction| interaction`, `skip_interactions: 0`, `remove_headers: []` and `replace_sensitive_data: []`.
- `file_read!`, `file_write!` and `file_delete!` are gone. `cassette_dir` is a path instead of a `Str`: `Path.utf8("tests/cassettes")`.
- `mode` defaults to `Replay`. Read it with `Vcr.parse_mode` to re-record without editing the test.
- `before_record` is now `filter_request` and `filter_response`, on roc-lang/http's types. `filter_request` also runs before matching, so a request it changes still replays. `before_replay` is gone: the response a cassette holds is what a replay returns.
- Credentials, cookies, URL passwords, Bearer tokens and names like `access_token` are kept out without any config, see [Keeping secrets out](#keeping-secrets-out-of-cassettes). Tokens and proofs that `replace_sensitive_data` replaced by value can go in `redact` by name. A cassette with `<ACCESS_TOKEN>` in it still matches.
- `Vcr.StoredCassette` and its parts are gone. Use `Vcr.decode_cassette`.

## Contributing

We're open for PRs! `nix develop` gives you the pinned Roc compiler. Run the tests from the repository root:

```bash
roc test package/main.roc # Unit tests, the expects next to the code
./tests.roc               # Every tests/*_test.roc through roc-spec
./tests.roc replay        # Only the tests with "replay" in their name
```

No test touches the network. They record from a mock `http_send!` and replay from cassettes.

## Status

`roc-vcr` is early but functional. The API will change as Roc evolves. If you're familiar with VCR in other languages, you'll feel right at home.

## Documentation

View the full API documentation at [https://niclas-ahden.github.io/roc-vcr/](https://niclas-ahden.github.io/roc-vcr/).
