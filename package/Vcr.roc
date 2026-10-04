## Record and replay HTTP interactions in your tests for speed and reliability.
##
## VCR (Video Cassette Recorder) is a testing pattern where HTTP requests and responses are recorded to disk the first time they're made, then replayed in subsequent test runs. This makes your tests fast, deterministic, and independent of external services.
##
## Inspired by Ruby's excellent [VCR gem](https://github.com/vcr/vcr). `roc-vcr` brings a similar approach to Roc.
import http.Header
import http.Method
import http.Request
import http.Response
import base64.Base64
import Scrub

Vcr := [].{

	## What a client does with its cassette. The mode is settled when [init!]
	## runs.
	##
	## `Replay`: answer every request from the cassette and never send one. A
	## missing cassette or interaction is an [Error]. This is the default.
	##
	## `Once`: record when the cassette does not exist yet, and replay
	## otherwise. An existing cassette is never added to.
	##
	## `Replace`: delete the cassette, then record every request into a new
	## one.
	Mode : [
		Replay,
		Once,
		Replace,
	]

	## Read a [Mode] from its name in any case. With the mode in an
	## environment variable, a test re-records without an edit:
	##
	## ```roc
	## mode = Vcr.parse_mode(Env.var_str!(OsStr.from_str("VCR_MODE")) ?? "replay")?
	## ```
	##
	## and then `VCR_MODE=replace ./tests.roc my_api`.
	parse_mode : Str -> Try(Mode, [UnknownMode(Str)])
	parse_mode = |name|
		match name.with_ascii_lowercased() {
			"replay" => Ok(Replay)
			"once" => Ok(Once)
			"replace" => Ok(Replace)
			_ => Err(UnknownMode(name))
		}

	## A request and the response it got, in the
	## [roc-lang/http](https://github.com/roc-lang/http) types a client takes
	## and returns.
	Interaction : {
		request : Request,
		response : Response,
	}

	## A cassette: what a client recorded, in order. Named after VHS cassette
	## tapes.
	Cassette : {
		name : Str,
		interactions : List(Interaction),
	}

	## The methods [init!] calls on `cassette_dir`. basic-cli's `Path` has them
	## all, so `Path.utf8("tests/cassettes")` works as it is. On another
	## platform, wrap its path type in one that has them.
	dir.CassetteDir(err) :
		where [
			dir.join : dir, Str -> dir,
			dir.display : dir -> Str,
			dir.exists! : dir => Try(Bool, err),
			dir.read_bytes! : dir => Try(List(U8), err),
			dir.write_bytes! : dir, List(U8) => Try({}, err),
			dir.delete! : dir => Try({}, err),
			dir.create_all! : dir => Try({}, err),
		]

	## How a client records and replays. Only `cassette_dir` and `http_send!`
	## have no default, so a config written inline at the call names those two
	## and whatever it changes:
	##
	## ```roc
	## client! = Vcr.init!({ cassette_dir: Path.utf8("tests/cassettes"), http_send!: Http.send! }, "github")?
	## ```
	##
	## A config bound to a name first has to carry a `Vcr.Config(_, _)`
	## annotation for the defaults to apply.
	##
	## `cassette_dir`: where the cassettes are, as your platform's path, see
	## [CassetteDir]. It is created when the first cassette is recorded.
	##
	## `http_send!`: sends a request for real while recording, such as
	## basic-cli's `Http.send!`.
	##
	## `mode`: see [Mode]. Defaults to `Replay`.
	##
	## `auto_redact`: `Off` turns off the built-in rules below, so that only
	## `redact`, `remove_headers`, `replace_sensitive_data` and your filters
	## keep secrets out. Record a cassette again after turning them off,
	## since the requests it holds were scrubbed by them. Defaults to `On`.
	##
	## `redact`: more names whose values are kept out of the cassette, on top
	## of the built-in ones. Defaults to `[]`.
	##
	## `dont_redact`: names whose secrets stay in the cassette after all,
	## whichever rule below found them, such as a token that pages through
	## results under a name the paging rule misses. Defaults to `[]`.
	##
	## `remove_headers`: names of headers to leave out, in any case. Defaults
	## to `[]`.
	##
	## `replace_sensitive_data`: exact text to replace, for a secret with no
	## name to find it by. Defaults to `[]`.
	##
	## `filter_request`: your own change to every request, made before the
	## filters above. Defaults to none.
	##
	## `filter_response`: your own change to every response that is recorded,
	## made before the filters above. Defaults to none.
	##
	## `match_headers`: names of request headers that a recording has to
	## match too, in any case. Defaults to `[]`, so headers do not count. See
	## [init!] for how a request is matched.
	##
	## Scrubbing is best effort. With no config, it keeps these out of a
	## cassette:
	##
	## - the credentials of `Authorization` and `Proxy-Authorization`, which
	##   keep their scheme, as in `Bearer <CREDENTIALS>`
	## - the values in `Cookie` and `Set-Cookie`, which keep the name of every
	##   cookie and the attributes, as in `session=<SESSION>; Path=/`
	## - the user and password of a URL, as in `https://<CREDENTIALS>@host`
	## - the token after `Bearer`
	## - the value of every name that ends in `token`, `secret`, `password`,
	##   `passwd`, `pwd`, `api_key`, `private_key`, `access_key` or
	##   `secret_key`, and of every name in `redact`
	##
	## It finds a secret by its name or its shape, so it misses some, such as
	## Google's `key=` parameter, Azure's `sig=` or a password in XML. Name the
	## secrets of the API you test with `redact`, `remove_headers`,
	## `replace_sensitive_data`, `filter_request` and `filter_response`, and
	## read a cassette before you commit it.
	##
	## A token that pages through results is no secret, so it stays: a name
	## that ends in `token` and has `page`, `next`, `continuation`, `sync` or
	## `cursor` in it, as `pageToken`, `NextToken` and `continuationToken` do.
	## Hidden, a paging token would make the requests for the pages after the
	## first all look the same, and a replay would answer each of them with
	## the second page.
	##
	## Every secret but the user and password of a URL is found by a name:
	## the header for `Authorization`, `Proxy-Authorization` and a header whose
	## name holds a secret, its own name for a cookie, `Bearer` for the token
	## after it, and the field for the rest. A secret found by a name in
	## `dont_redact` stays as it is, with nothing inside it replaced, unless
	## `redact` has the name too.
	##
	## A name is found in any case and with or without `_` and `-`, so
	## `access_token`, `Access-Token` and `accessToken` are one name. It is
	## found as a header, a query or form parameter (`name=value`), a JSON field
	## (`"name": value`), a JSON field inside a JSON string, and a
	## `name: value` line. Its value becomes the name in upper case, as in
	## `access_token=<ACCESS_TOKEN>`, and a JSON number becomes that text in
	## quotes, so the JSON stays valid. A Boolean is left, since it is no
	## secret and a placeholder would not decode as one, and so are `null`,
	## an object and a list. A body that is not UTF-8 is not searched.
	##
	## A request is filtered on its way into the cassette and again before it
	## is matched against it, so a request that was changed when it was
	## recorded still matches when it is replayed. A response is filtered only
	## when it is recorded, and the one handed back while recording is the
	## real one.
	Config(dir, err) := {
		cassette_dir : dir,
		http_send! : Request => Try(Response, err),
		mode : Mode ?? Replay,
		auto_redact : [On, Off] ?? On,
		redact : List(Str) ?? [],
		dont_redact : List(Str) ?? [],
		remove_headers : List(Str) ?? [],
		replace_sensitive_data : List({ find : Str, replace : Str }) ?? [],
		filter_request : (Request -> Request) ?? |request| request,
		filter_response : (Response -> Response) ?? |response| response,
		match_headers : List(Str) ?? [],
	}

	## Ways [init!] can fail. Each carries a message naming the cassette file.
	##
	## `CassetteNotFound`: `Replay` mode and there is no cassette file
	##
	## `CassetteReadFailed`: the cassette file is there but could not be read
	##
	## `CassetteDecodeFailed`: the cassette file is not a valid cassette
	##
	## `CassetteDeleteFailed`: `Replace` mode and the old cassette could not be
	## deleted
	InitError : [
		CassetteNotFound(Str),
		CassetteReadFailed(Str),
		CassetteDecodeFailed(Str),
		CassetteDeleteFailed(Str),
	]

	## Ways a client made by [init!] can fail, on top of whatever `http_send!`
	## fails with (`e`). Each carries a message naming the cassette file.
	##
	## `CassetteReadFailed` and `CassetteDecodeFailed`: a client that records
	## could not read the cassette it adds to
	##
	## `CassetteSaveFailed`: the cassette could not be written
	##
	## `InteractionNotFound`: no recorded interaction matches the request. The
	## message names the closest one and how it differs.
	Error(e) : [
		CassetteReadFailed(Str),
		CassetteDecodeFailed(Str),
		CassetteSaveFailed(Str),
		InteractionNotFound(Str),
		..e,
	]

	## Create a client for the cassette `<cassette_dir>/<cassette_name>.json`.
	## The client has the type of `http_send!`, so the code under test takes
	## its HTTP function as an argument and gets `Http.send!` in production and
	## the client in a test:
	##
	## ```roc
	## client! = Vcr.init!({ cassette_dir: Path.utf8("tests/cassettes"), http_send!: Http.send! }, "github")?
	## repo = fetch_repo!(client!, "roc-lang/roc")?
	## ```
	##
	## Use one client per cassette. The mode is settled when `init!` runs: that
	## is when `Replace` deletes the old cassette, when `Once` looks for one to
	## decide whether the client records or replays, and when a client that
	## replays reads its cassette. A client never sees what another client does
	## to its cassette.
	##
	## A cassette that cannot be settled is an [InitError] from `init!`, so it
	## fails the test where the client is made. The code under test never gets
	## to handle it, and cannot hide it.
	##
	## A recording answers a request when it has the same method, URI and body,
	## and the same values for every header in `match_headers`, all compared
	## after the filters. Other headers do not count. A replay answers a
	## request with the first recording that matches it, so a request sent
	## again gets the same answer. When a test expects a new answer to the
	## same request, give the part of the test after the change a client and a
	## cassette of its own.
	##
	## The client reports VCR failures as an [Error] when it is called, next to
	## the errors of `http_send!`. The error type of `http_send!` therefore has
	## to be an open tag union, which an inferred type and the return type of a
	## platform function are. An annotated one ends in `..`, as in
	## `[MyHttpError, ..]`.
	init! : Config(dir, Error(e)), Str => Try((Request => Try(Response, Error(e))), InitError) where [dir.CassetteDir(file_err)]
	init! = |config, cassette_name| {
		http_send! = config.http_send!
		filter_request = config.filter_request
		filter_response = config.filter_response
		dir = config.cassette_dir
		filters = filters_from({ auto_redact: config.auto_redact, redact: config.redact, dont_redact: config.dont_redact }, config.remove_headers, config.replace_sensitive_data)
		match_headers = config.match_headers.map(|name| name.with_ascii_lowercased())
		file = dir.join("${cassette_name}.json")
		path = file.display()
		plan = settle!(config.mode, file, path, filters)?

		Ok(|request| {
			match plan {
				Record => {
					cassette = if file.exists!() ? |err| CassetteReadFailed("${path}: ${Str.inspect(err)}") {
						load!(file, path)?
					} else {
						{ name: cassette_name, interactions: [] }
					}
					response = http_send!(request)?
					recorded = {
						request: clean_request(filter_request(request), filters),
						response: clean_response(filter_response(response), filters),
					}
					bytes = Vcr.encode_cassette({ ..cassette, interactions: cassette.interactions.append(recorded) })
					dir.create_all!() ? |err| CassetteSaveFailed("${path}: ${Str.inspect(err)}")
					file.write_bytes!(bytes) ? |err| CassetteSaveFailed("${path}: ${Str.inspect(err)}")
					Ok(response)
				}

				Replay(interactions) => {
					wanted = clean_request(filter_request(request), filters)
					interaction = find_interaction(interactions, wanted, match_headers)
						? |NotFound| InteractionNotFound(explain_miss(interactions, wanted, match_headers, path))
					Ok(interaction.response)
				}
			}
		})
	}

	## Decode the bytes of a cassette file, for reading one in your own code.
	## Both this version's format and the byte lists of 0.1.0 decode.
	decode_cassette : List(U8) -> Try(Cassette, [CassetteDecodeFailed(Str)])
	decode_cassette = |bytes| {
		text = Str.from_utf8_lossy(bytes)
		current : Try(StoredCassette, _)
		current = Json.parse(text)
		match current {
			Ok(stored) => stored_to_cassette(stored)
			Err(current_err) => {
				legacy : Try(LegacyCassette, _)
				legacy = Json.parse(text)
				match legacy {
					Ok(stored) => Ok(legacy_to_cassette(stored))
					# The error for the current format is the one worth reading
					Err(_) => Err(CassetteDecodeFailed(Str.inspect(current_err)))
				}
			}
		}
	}

	## Encode a cassette as the bytes of a cassette file: JSON with one field
	## per line, so a change to a recording reads well in a diff. A body is a
	## string when it is UTF-8, and base64 in `body_base64` when it is not.
	## The timeout of a request is not stored.
	encode_cassette : Cassette -> List(U8)
	encode_cassette = |cassette| {
		interactions =
			if cassette.interactions.is_empty() {
				"[]"
			} else {
				"[\n${Str.join_with(cassette.interactions.map(encode_interaction), ",\n")}\n  ]"
			}
		Str.to_utf8("{\n  \"name\": ${Json.to_str(cassette.name)},\n  \"interactions\": ${interactions}\n}\n")
	}
}

## What a client does with every request it gets. A client that replays holds
## the interactions of its cassette, read once when the client was made.
Plan : [Record, Replay(List(Vcr.Interaction))]

## Settle the mode into a [Plan]. `Replace` deletes the old cassette here.
settle! : Vcr.Mode, file, Str, Filters => Try(Plan, Vcr.InitError) where [file.Vcr.CassetteDir(err)]
settle! = |mode, file, path, filters| {
	exists = file.exists!() ? |err| CassetteReadFailed("${path}: ${Str.inspect(err)}")
	match mode {
		Replay =>
			if exists {
				Ok(Replay(replayable(load!(file, path)?, filters)))
			} else {
				Err(CassetteNotFound("${path} does not exist. Record it by running in Once or Replace mode"))
			}
		Once => if exists Ok(Replay(replayable(load!(file, path)?, filters))) else Ok(Record)
		Replace => {
			if exists {
				file.delete!() ? |err| CassetteDeleteFailed("${path}: ${Str.inspect(err)}")
			}
			Ok(Record)
		}
	}
}

## Read and decode the cassette in `file`.
load! : file, Str => Try(Vcr.Cassette, [CassetteReadFailed(Str), CassetteDecodeFailed(Str)]) where [file.Vcr.CassetteDir(err)]
load! = |file, path| {
	bytes = file.read_bytes!() ? |err| CassetteReadFailed("${path}: ${Str.inspect(err)}")
	Vcr.decode_cassette(bytes).map_err(|CassetteDecodeFailed(message)| CassetteDecodeFailed("${path}: ${message}"))
}

## The interactions of `cassette` with their requests filtered the way a
## request about to be matched is. Filtering what is already filtered changes
## nothing, and a cassette that a config with fewer filters recorded, or an
## older version that kept out less, still matches what it holds.
replayable : Vcr.Cassette, Filters -> List(Vcr.Interaction)
replayable = |cassette, filters|
	cassette.interactions.map(|interaction| { ..interaction, request: clean_request(interaction.request, filters) })

# Filtering

## The filters of a config, prepared once per client
Filters : {
	rules : Scrub.Rules,
	remove_headers : List(Str),
	replace_sensitive_data : List({ find : Str, replace : Str }),
}

## The filters of a config, with the headers to remove in lower case
filters_from : { auto_redact : [On, Off], redact : List(Str), dont_redact : List(Str) }, List(Str), List({ find : Str, replace : Str }) -> Filters
filters_from = |{ auto_redact, redact, dont_redact }, remove_headers, replace_sensitive_data| {
	rules: Scrub.rules_from(auto_redact, redact, dont_redact),
	remove_headers: remove_headers.map(|name| name.with_ascii_lowercased()),
	replace_sensitive_data,
}

## Apply the built-in filters to a request
clean_request : Request, Filters -> Request
clean_request = |request, filters|
	request
		.with_uri(clean_text(request.uri(), filters))
		.with_headers(clean_headers(request.headers(), filters))
		.with_body(clean_body(request.body(), filters))

## Apply the built-in filters to a response
clean_response : Response, Filters -> Response
clean_response = |response, filters|
	response
		.with_headers(clean_headers(response.headers(), filters))
		.with_body(clean_body(response.body(), filters))

## Scrub a piece of text, then replace the exact text the config names
clean_text : Str, Filters -> Str
clean_text = |text, filters| replace_data(Scrub.text(text, filters.rules), filters)

## `text` with what `replace_sensitive_data` finds replaced
replace_data : Str, Filters -> Str
replace_data = |text, filters|
	filters.replace_sensitive_data.fold(text, |acc, { find, replace }| acc.replace_each(find, replace))

## Drop the removed headers, in any case, and scrub the values of the rest
clean_headers : List(Header), Filters -> List(Header)
clean_headers = |headers, filters|
	headers
		.keep_if(|header| !(filters.remove_headers.contains(header.name.with_ascii_lowercased())))
		.map(|header| { name: header.name, value: replace_data(Scrub.header(header.name, header.value, filters.rules), filters) })

## Clean a body. A body that is not UTF-8 is left as it is.
clean_body : List(U8), Filters -> List(U8)
clean_body = |bytes, filters|
	match Str.from_utf8(bytes) {
		Ok(text) => Str.to_utf8(clean_text(text, filters))
		Err(_) => bytes
	}

# Matching

## Whether a recorded request answers `wanted`: the same method, URI and
## body, and the same values for every header in `match_headers`, which are
## in lower case
same_request : Request, Request, List(Str) -> Bool
same_request = |recorded, wanted, match_headers|
	same_route(recorded, wanted) and recorded.body() == wanted.body() and different_header(recorded, wanted, match_headers).is_err()

## Whether two requests have the same method and URI
same_route : Request, Request -> Bool
same_route = |recorded, wanted| recorded.method() == wanted.method() and recorded.uri() == wanted.uri()

## The first header in `match_headers` whose values differ between two
## requests
different_header : Request, Request, List(Str) -> Try(Str, [NotFound])
different_header = |recorded, wanted, match_headers|
	match_headers
		.find_first(|name| header_values(recorded, name) != header_values(wanted, name))
		.map_err(|_| NotFound)

## The values of every header called `name`, which is in lower case, in the
## order they come in
header_values : Request, Str -> List(Str)
header_values = |request, name|
	request.headers()
		.keep_if(|header| header.name.with_ascii_lowercased() == name)
		.map(|header| header.value)

## The first interaction that answers `wanted`
find_interaction : List(Vcr.Interaction), Request, List(Str) -> Try(Vcr.Interaction, [NotFound])
find_interaction = |interactions, wanted, match_headers|
	interactions
		.find_first(|interaction| same_request(interaction.request, wanted, match_headers))
		.map_err(|_| NotFound)

## Why no interaction answers `wanted`, naming the closest recording and how
## to record the request. A recording with the same method, URI and body is
## closest, and then one with the same method and URI.
explain_miss : List(Vcr.Interaction), Request, List(Str), Str -> Str
explain_miss = |interactions, wanted, match_headers, path| {
	recorded = interactions.map(|interaction| interaction.request)
	same_body = recorded.find_first(|request| same_route(request, wanted) and request.body() == wanted.body())
	hint =
		match (same_body, recorded.find_first(|request| same_route(request, wanted))) {
			(Ok(request), _) => {
				name = different_header(request, wanted, match_headers) ?? ""
				"It has ${describe(request)}, whose ${name} header differs: recorded ${header_text(request, name)}, sent ${header_text(wanted, name)}."
			}
			(_, Ok(request)) => {
				at = first_difference(request.body(), wanted.body())
				"It has ${describe(request)}, whose body differs from byte ${at.to_str()}: recorded ${excerpt(request.body(), at)}, sent ${excerpt(wanted.body(), at)}."
			}
			_ =>
				if recorded.is_empty() {
					"It has no interactions."
				} else {
					shown = recorded.take_first(5).map(describe)
					more = if recorded.len() > 5 ", and ${(recorded.len() - 5).to_str()} more" else ""
					"It has ${Str.join_with(shown, ", ")}${more}."
				}
		}
	"No recorded interaction in ${path} matches ${describe(wanted)}. ${hint} Run in Replace mode to record the cassette again."
}

## The values of the header `name` in `request`, quoted, or `none`
header_text : Request, Str -> Str
header_text = |request, name|
	match header_values(request, name) {
		[] => "none"
		values => Str.inspect(Str.join_with(values, ", "))
	}

## A request in words, as in `POST https://x.se/a with a 12 byte body`
describe : Request -> Str
describe = |request| {
	body = if request.body().is_empty() "" else " with a ${request.body().len().to_str()} byte body"
	"${request.method_str()} ${request.uri()}${body}"
}

## The index of the first byte where `a` and `b` differ
first_difference : List(U8), List(U8) -> U64
first_difference = |a, b| {
	len = if a.len() < b.len() a.len() else b.len()
	var $i = 0
	while $i < len and a.get($i) == b.get($i) {
		$i = $i + 1
	}
	$i
}

## Up to 40 bytes of `body` from `at`, quoted, with 10 before it for context
excerpt : List(U8), U64 -> Str
excerpt = |body, at| {
	start = if at > 10 at - 10 else 0
	text = Str.from_utf8_lossy(body.sublist({ start, len: 40 }))
	if at >= body.len() "the end of the body" else Str.inspect(text)
}

## HTTP method from its name in a cassette file
method_from_str : Str -> Method
method_from_str = |name|
	match name {
		"GET" => GET
		"POST" => POST
		"PUT" => PUT
		"DELETE" => DELETE
		"HEAD" => HEAD
		"OPTIONS" => OPTIONS
		"PATCH" => PATCH
		"CONNECT" => CONNECT
		"TRACE" => TRACE
		"QUERY" => QUERY
		other => Unknown(other)
	}

# The cassette file

## A body as a cassette file holds it: `body` when the bytes are UTF-8, and
## `body_base64` when they are not
StoredBody : { body : Try(Str, [Missing]), body_base64 : Try(Str, [Missing]) }

## A header as a cassette file holds it
StoredHeader : { name : Str, value : Str }

## A request as a cassette file holds it. The timeout is not stored.
StoredRequest : {
	method : Str,
	uri : Str,
	headers : List(StoredHeader),
	body : Try(Str, [Missing]),
	body_base64 : Try(Str, [Missing]),
}

## A response as a cassette file holds it
StoredResponse : {
	status : U16,
	headers : List(StoredHeader),
	body : Try(Str, [Missing]),
	body_base64 : Try(Str, [Missing]),
}

## A cassette file
StoredCassette : {
	name : Str,
	interactions : List({ request : StoredRequest, response : StoredResponse }),
}

## A cassette file as 0.1.0 wrote it, with bodies as lists of bytes
LegacyCassette : {
	name : Str,
	interactions : List(
		{
			request : { method : Str, uri : Str, headers : List(StoredHeader), body : List(U8) },
			response : { status : U16, headers : List(StoredHeader), body : List(U8) },
		},
	),
}

## The bytes of a stored body
body_from_stored : StoredBody -> Try(List(U8), [CassetteDecodeFailed(Str)])
body_from_stored = |stored|
	match (stored.body, stored.body_base64) {
		(Ok(text), _) => Ok(Str.to_utf8(text))
		(_, Ok(encoded)) => Base64.decode(encoded).map_err(|err| CassetteDecodeFailed("body_base64 is not base64: ${Str.inspect(err)}"))
		_ => Ok([])
	}

## Stored headers as roc-lang/http headers. Mapped one by one, so the type
## the cassette file is parsed into stays a plain record.
to_headers : List(StoredHeader) -> List(Header)
to_headers = |headers| headers.map(|header| { name: header.name, value: header.value })

## A request from what a cassette file holds
request_from : Str, Str, List(StoredHeader), List(U8) -> Request
request_from = |method, uri, headers, body|
	Request.from_method(method_from_str(method))
		.with_uri(uri)
		.with_headers(to_headers(headers))
		.with_body(body)

## A response from what a cassette file holds
response_from : U16, List(StoredHeader), List(U8) -> Response
response_from = |status, headers, body|
	Response.from_status(status)
		.with_headers(to_headers(headers))
		.with_body(body)

## Convert a parsed cassette file to a [Vcr.Cassette]
stored_to_cassette : StoredCassette -> Try(Vcr.Cassette, [CassetteDecodeFailed(Str)])
stored_to_cassette = |stored| {
	interactions = stored.interactions.map_try(
		|{ request, response }| {
			request_body = body_from_stored({ body: request.body, body_base64: request.body_base64 })?
			response_body = body_from_stored({ body: response.body, body_base64: response.body_base64 })?
			Ok({
				request: request_from(request.method, request.uri, request.headers, request_body),
				response: response_from(response.status, response.headers, response_body),
			})
		},
	)?
	Ok({ name: stored.name, interactions })
}

## Convert a parsed 0.1.0 cassette file to a [Vcr.Cassette]
legacy_to_cassette : LegacyCassette -> Vcr.Cassette
legacy_to_cassette = |stored| {
	name: stored.name,
	interactions: stored.interactions.map(
		|{ request, response }| {
			request: request_from(request.method, request.uri, request.headers, request.body),
			response: response_from(response.status, response.headers, response.body),
		},
	),
}

## One interaction of a cassette file, indented to sit in its list
encode_interaction : Vcr.Interaction -> Str
encode_interaction = |{ request, response }|
	\\    {
	\\      "request": {
	\\        "method": ${Json.to_str(request.method_str())},
	\\        "uri": ${Json.to_str(request.uri())},
	\\        "headers": ${encode_headers(request.headers())},
	\\        ${encode_body(request.body())}
	\\      },
	\\      "response": {
	\\        "status": ${response.status().to_str()},
	\\        "headers": ${encode_headers(response.headers())},
	\\        ${encode_body(response.body())}
	\\      }
	\\    }

## Headers, one per line
encode_headers : List(Header) -> Str
encode_headers = |headers|
	if headers.is_empty() {
		"[]"
	} else {
		lines = headers.map(|header| "          { \"name\": ${Json.to_str(header.name)}, \"value\": ${Json.to_str(header.value)} }")
		"[\n${Str.join_with(lines, ",\n")}\n        ]"
	}

## A body field: text when the bytes are UTF-8, base64 when they are not
encode_body : List(U8) -> Str
encode_body = |bytes|
	match Str.from_utf8(bytes) {
		Ok(text) => "\"body\": ${Json.to_str(text)}"
		Err(_) => "\"body_base64\": ${Json.to_str(Base64.encode(bytes))}"
	}

# Tests, run with roc test package/main.roc

## The headers of a request or response as plain pairs, to compare
pairs : List(Header) -> List((Str, Str))
pairs = |headers| headers.map(|header| (header.name, header.value))

test_request : Request
test_request =
	Request.from_method(POST)
		.with_uri("https://api.example.com/things?account=SECRET")
		.add_header("Authorization", "Bearer SECRET")
		.add_header("Accept", "application/json")
		.with_body(Str.to_utf8("{\"account\":\"SECRET\"}"))

test_filters : Filters
test_filters = filters_from({ auto_redact: On, redact: [], dont_redact: [] }, ["accept"], [{ find: "SECRET", replace: "[REDACTED]" }])

expect Vcr.parse_mode("Replace") == Ok(Replace)
expect Vcr.parse_mode("once") == Ok(Once)
expect Vcr.parse_mode("record") == Err(UnknownMode("record"))

# A method comes back from its name, an unknown one included
expect ["GET", "QUERY", "BREW"].all(|name| Request.from_method(method_from_str(name)).method_str() == name)

# Removed headers go whatever their case, Authorization keeps its scheme, and
# the exact text is replaced everywhere
expect {
	cleaned = clean_request(test_request, test_filters)
	uri_ok = cleaned.uri() == "https://api.example.com/things?account=[REDACTED]"
	headers_ok = pairs(cleaned.headers()) == [("Authorization", "Bearer <CREDENTIALS>")]
	body_ok = cleaned.body() == Str.to_utf8("{\"account\":\"[REDACTED]\"}")
	uri_ok and headers_ok and body_ok and cleaned.method_str() == "POST"
}

expect {
	cleaned = clean_response(
		Response.from_status(200)
			.add_header("Set-Cookie", "session=SECRET; Path=/; HttpOnly")
			.add_header("Accept", "text/plain")
			.with_body(Str.to_utf8("SECRET data")),
		test_filters,
	)
	headers_ok = pairs(cleaned.headers()) == [("Set-Cookie", "session=<SESSION>; Path=/; HttpOnly")]
	body_ok = cleaned.body() == Str.to_utf8("[REDACTED] data")
	headers_ok and body_ok and cleaned.status() == 200
}

# A body that is not UTF-8 is left alone
expect clean_body([0xff, 0xfe], test_filters) == [0xff, 0xfe]

# The first matching interaction answers
expect {
	make = |uri, status| { request: Request.from_method(GET).with_uri(uri), response: Response.from_status(status) }
	interactions = [make("https://a.se", 1), make("https://b.se", 2), make("https://a.se", 3)]
	found = find_interaction(interactions, Request.from_method(GET).with_uri("https://a.se"), [])
	missing = find_interaction(interactions, Request.from_method(POST).with_uri("https://a.se"), [])
	found.map_ok(|interaction| interaction.response.status()) == Ok(1) and missing.is_err()
}

# Headers count only when named, in any case, by every value they have
expect {
	request = Request.from_method(GET).with_uri("https://a.se")
	recorded = [{ request: request.add_header("X-Version", "1").add_header("Accept", "a"), response: Response.from_status(200) }]
	status = |wanted, names| find_interaction(recorded, wanted, names).map_ok(|interaction| interaction.response.status())
	unnamed = status(request.add_header("X-Version", "2"), []) == Ok(200)
	same = status(request.add_header("x-version", "1").add_header("Accept", "b"), ["x-version"]) == Ok(200)
	differs = status(request.add_header("X-Version", "2"), ["x-version"]).is_err()
	missing = status(request, ["x-version"]).is_err()
	extra = status(request.add_header("X-Version", "1").add_header("X-Version", "1"), ["x-version"]).is_err()
	unnamed and same and differs and missing and extra
}

# A miss on a header names the header and both values
expect {
	recorded = Request.from_method(GET).with_uri("https://a.se").add_header("X-Version", "1")
	message = explain_miss([{ request: recorded, response: Response.from_status(200) }], recorded.with_headers([]), ["x-version"], "c.json")
	message == "No recorded interaction in c.json matches GET https://a.se. It has GET https://a.se, whose x-version header differs: recorded \"1\", sent none. Run in Replace mode to record the cassette again."
}

# A miss on the body names the recording and the first byte that differs
expect {
	recorded = Request.from_method(POST).with_uri("https://a.se").with_body(Str.to_utf8("{\"n\":1}"))
	wanted = recorded.with_body(Str.to_utf8("{\"n\":2}"))
	message = explain_miss([{ request: recorded, response: Response.from_status(200) }], wanted, [], "c.json")
	message == "No recorded interaction in c.json matches POST https://a.se with a 7 byte body. It has POST https://a.se with a 7 byte body, whose body differs from byte 5: recorded \"{\\\"n\\\":1}\", sent \"{\\\"n\\\":2}\". Run in Replace mode to record the cassette again."
}

# A miss on the URI lists what the cassette has
expect {
	recorded = Request.from_method(GET).with_uri("https://a.se")
	message = explain_miss([{ request: recorded, response: Response.from_status(200) }], recorded.with_uri("https://b.se"), [], "c.json")
	message == "No recorded interaction in c.json matches GET https://b.se. It has GET https://a.se. Run in Replace mode to record the cassette again."
}

# A cassette survives a full encode and decode round trip, binary bodies and
# an unknown method included
expect {
	cassette = {
		name: "round_trip",
		interactions: [
			{
				request: test_request,
				response: Response.from_status(200)
					.add_header("content-type", "application/json")
					.with_body(Str.to_utf8("{\"å\": \"line\\nbreak\"}")),
			},
			{
				request: Request.from_method(Unknown("BREW")).with_uri("https://a.se"),
				response: Response.from_status(201).with_body([0xff, 0x00, 0x89, 0x50]),
			},
		],
	}
	encoded = Vcr.encode_cassette(cassette)
	match Vcr.decode_cassette(encoded) {
		Ok(decoded) => {
			second = decoded.interactions.get(1)
			Vcr.encode_cassette(decoded) == encoded
			and decoded.interactions.map(|interaction| interaction.request.method_str()) == ["POST", "BREW"]
			and second.map_ok(|interaction| interaction.response.body()) == Ok([0xff, 0x00, 0x89, 0x50])
		}
		Err(_) => Bool.False
	}
}

# Text bodies are stored as text, and binary ones as base64
expect {
	cassette = {
		name: "bodies",
		interactions: [
			{
				request: test_request.with_body(Str.to_utf8("hi")),
				response: Response.from_status(200).with_body([0xff]),
			},
		],
	}
	text = Str.from_utf8_lossy(Vcr.encode_cassette(cassette))
	text.contains("\"body\": \"hi\"") and text.contains("\"body_base64\": \"/w==\"")
}

# Cassettes written by 0.1.0 keep decoding. Its encoder ordered fields
# alphabetically, escaped forward slashes as \/ and wrote bodies as bytes.
expect {
	disk_json = "{\"interactions\":[{\"request\":{\"body\":[],\"headers\":[{\"name\":\"Accept\",\"value\":\"application\\/json\"}],\"method\":\"GET\",\"uri\":\"https:\\/\\/example.com\\/a\"},\"response\":{\"body\":[123,125],\"headers\":[],\"status\":200}}],\"name\":\"disk\"}"
	match Vcr.decode_cassette(Str.to_utf8(disk_json)) {
		Ok(decoded) =>
			match decoded.interactions {
				[{ request, response }] =>
					decoded.name == "disk"
					and request.method_str() == "GET"
					and request.uri() == "https://example.com/a"
					and pairs(request.headers()) == [("Accept", "application/json")]
					and request.body() == []
					and response.status() == 200
					and response.body() == [123, 125]
				_ => Bool.False
			}
		Err(_) => Bool.False
	}
}

expect
	match Vcr.decode_cassette(Str.to_utf8("{ this is not valid json }")) {
		Err(CassetteDecodeFailed(_)) => Bool.True
		_ => Bool.False
	}
