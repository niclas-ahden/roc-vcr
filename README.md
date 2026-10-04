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

Your app passes it basic-cli's `Http.send!`, as in `Invoices.get!(Http.send!, token, "42")`. A test passes a VCR client instead. The client has the same type, since both take and return the `Request` and `Response` of [roc-lang/http](https://github.com/roc-lang/http):

```roc
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.28.0/AP9SGT1yrhCKcFxKcoA5tBkNCM6ibBjBxcQGMTb6krev.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/2.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	vcr: "https://github.com/niclas-ahden/roc-vcr/releases/download/0.2.0/EDAmTVryPRkfrpLJyyDNEqftSQ7TyUWN9XomuxA1h1dE.tar.zst",
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

Run it once with `VCR_MODE=once` and a real token. The request is sent and recorded in `tests/cassettes/invoice.json`, with the token [scrubbed out](#keeping-secrets-out-of-cassettes). Read the file to check that no other secret is left in it, then commit it. Every later run replays it without touching the network.

See `examples/example.roc` for a complete working example that replays from a committed cassette.

## Modes

- **`Replay`** (the default) - Only replay from the cassette, and never send a request. A missing cassette or interaction is an error
- **`Once`** - Record if the cassette doesn't exist, replay otherwise. It never adds to an existing cassette
- **`Replace`** - Delete the cassette and record every request into a new one

Read the mode from an environment variable, as the quick start does, and you re-record a test without editing it:

```bash
VCR_MODE=replace ./tests.roc create_invoice
```

Since the default is `Replay`, a test run in CI never reaches the network, and a missing recording fails loudly instead of being made there.

There is no `Record` mode, because people disagree on what it means (`Replace`, `Once`, or adding to an existing cassette). The names above say what they do.

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
| `auto_redact` | `[On, Off]` | `On` | `Off` turns off the built-in scrubbing rules, see [Scrubbing only what you name](#scrubbing-only-what-you-name) |
| `redact` | `List(Str)` | `[]` | More names whose values are kept out of the cassette, see [Keeping secrets out](#keeping-secrets-out-of-cassettes) |
| `dont_redact` | `List(Str)` | `[]` | Names whose values stay in the cassette after all, see [Leaving a value in](#leaving-a-value-in) |
| `remove_headers` | `List(Str)` | `[]` | Headers to leave out of the cassette, in any case |
| `replace_sensitive_data` | `List({ find : Str, replace : Str })` | `[]` | Exact text to replace |
| `filter_request` | `Request -> Request` | no change | Your own change to every request |
| `filter_response` | `Response -> Response` | no change | Your own change to every recorded response |
| `match_headers` | `List(Str)` | `[]` | Request headers that have to match too, in any case, see [How request matching works](#how-request-matching-works) |

## Keeping secrets out of cassettes

Cassettes should be committed, so secrets have to stay out of them. `roc-vcr` scrubs them on a best effort basis. With no config, it hides:

- the credentials of `Authorization` and `Proxy-Authorization`: `Bearer <CREDENTIALS>`
- the value of every cookie in `Cookie` and `Set-Cookie`: `session=<SESSION>; Path=/; HttpOnly`
- the user and password of a URL: `postgres://<CREDENTIALS>@db/app`
- the token after `Bearer`, wherever it is
- the value of every name that ends in `token`, `secret`, `password`, `passwd`, `pwd`, `api_key`, `private_key`, `access_key` or `secret_key`, in a header, a query or form parameter, a JSON field or a `name: value` line: `access_token=<ACCESS_TOKEN>`

A name is found in any case and with or without `_` and `-`, so `access_token`, `Access-Token` and `accessToken` are the same name.

The scrubber cannot know every API. It misses secrets under other names or with no name at all, like Google's `key=` parameter, Azure's `sig=` or a password in XML. Tell it about the secrets of the API you test, and verify your cassettes don't contain secrets before you commit them.

```roc
client! = Vcr.init!(
	{
		cassette_dir: Path.utf8("tests/cassettes"),
		http_send!: Http.send!,
		redact: ["key", "sig"],
		remove_headers: ["X-Request-Id"],
		replace_sensitive_data: [{ find: account_id, replace: "<ACCOUNT_ID>" }],
	},
	"insights",
)?
```

- **`redact`** hides the values of more names, found the same way as the built-in ones.
- **`remove_headers`** leaves headers out of the cassette.
- **`replace_sensitive_data`** replaces exact text, for a secret you know that has no name.
- **`filter_request`** and **`filter_response`** take your own function for anything else.

A request is scrubbed the same way before it is matched against the cassette, so a test replays without real credentials.

### Leaving a value in

Some names look like secrets but are not. A token that pages through results has to stay, or the requests for every page after the first look the same. A name that ends in `token` and contains `page`, `next`, `continuation`, `sync` or `cursor`, like `nextPageToken`, stays by default. Put any other such name in `dont_redact`:

```roc
client! = Vcr.init!({ cassette_dir: Path.utf8("tests/cassettes"), http_send!: Http.send!, dont_redact: ["resume_token"] }, "changes")?
```

`dont_redact` works on every built-in rule except URL passwords. So `dont_redact: ["lang"]` keeps `lang=en` in a `Cookie` header while `session` stays hidden. A name in both `redact` and `dont_redact` is hidden.

### Scrubbing only what you name

`auto_redact: Off` turns off every built-in rule, for when they hide something your test needs or you would rather name every secret yourself. Then only `redact`, `remove_headers`, `replace_sensitive_data` and your filters keep secrets out:

```roc
client! = Vcr.init!({ cassette_dir: Path.utf8("tests/cassettes"), http_send!: Http.send!, auto_redact: Off, redact: ["authorization", "access_token", "session_id"] }, "billing")?
```

With the rules off, even `Authorization` and cookies are recorded as they are, so name every secret your test sends or gets, as the example does with `authorization`. That also keeps a replay without the real credentials matching. Record a cassette again after turning the rules off, since the requests it holds were scrubbed by them.

The [API docs](https://niclas-ahden.github.io/roc-vcr/) have the exact rules, such as what happens to JSON numbers and Booleans.

## How request matching works

A recorded interaction answers a request when they have the same:

- HTTP method
- full URI, query parameters included
- body
- values for the headers named in `match_headers`, if any

All of them are compared after filtering and scrubbing, and the first match wins. Other headers do not count. When a header decides what the server answers, like an API version, name it in `match_headers`:

```roc
client! = Vcr.init!({ ..config, match_headers: ["Api-Version"] }, "invoice_v2")?
```

When part of a request changes on every run, like a timestamp or a nonce, remove it in `filter_request` and it no longer affects matching:

```roc
without_timestamp = |request|
	match request.uri().split_first("&ts=") {
		Ok({ before, after: _ }) => request.with_uri(before)
		Err(_) => request
	}
```

When nothing matches, the error names the closest recording and how it differs:

```
No recorded interaction in tests/cassettes/invoice.json matches POST https://api.example.com/invoice with a 58 byte body. It has POST https://api.example.com/invoice with a 58 byte body, whose body differs from byte 46: recorded "amount\":100,\"rows\":[]}", sent "amount\":101,\"rows\":[]}". Run in Replace mode to record the cassette again.
```

## Handling multiple identical requests

A replay answers a request with the first recording that matches it, so a request sent again gets the same answer. When a test expects a new answer to the same request (say it reads an invoice, pays it and reads it again), record the part after the change into a cassette of its own:

```roc
client! = Vcr.init!(config, "pay_invoice")?
unpaid = Invoices.get!(client!, token, "42")?
Invoices.pay!(client!, token, "42")?

paid_invoice_client! = Vcr.init!(config, "paid_invoice")?
paid = Invoices.get!(paid_invoice_client!, token, "42")?
```

When your code repeats a request by itself, as when it polls a job until it is done, a replay gives it the first recorded answer every time. A client cannot count the requests it has answered, since a Roc function keeps no state between calls, so a test of such code needs a fake `http_send!` of its own instead.

## Errors

Every error carries a message that names the cassette file.

| Error | From | When |
|-------|------|------|
| `CassetteNotFound(Str)` | `Vcr.init!` | `Replay` mode and there is no cassette file |
| `CassetteDeleteFailed(Str)` | `Vcr.init!` | `Replace` mode and the old cassette could not be deleted |
| `CassetteReadFailed(Str)` | both | The cassette file is there but could not be read |
| `CassetteDecodeFailed(Str)` | both | The cassette file is not valid cassette JSON |
| `InteractionNotFound(Str)` | the client | No recorded interaction matches the request |
| `CassetteSaveFailed(Str)` | the client | The cassette could not be written |

A missing or broken cassette fails at `Vcr.init!(...)?`, before the code under test runs. The errors of the client reach your test through the code under test, next to the errors of `http_send!`.

That is why the error type of `http_send!` has to be an open tag union. `Http.send!` and an inferred type already are. If you annotate one yourself, end it with `..`, as in `Try(Response, [MyHttpError, ..])`.

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

A body that is not UTF-8, like an image, is stored as base64 in `body_base64` and replays byte for byte. To read or write a cassette in your own code, use `Vcr.decode_cassette` and `Vcr.encode_cassette`.

## Documentation

View the full API documentation at [https://niclas-ahden.github.io/roc-vcr/](https://niclas-ahden.github.io/roc-vcr/).
