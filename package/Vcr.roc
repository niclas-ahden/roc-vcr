## Record and replay HTTP interactions in your tests for speed and reliability.
##
## VCR (Video Cassette Recorder) is a testing pattern where HTTP requests and responses are recorded to disk the first time they're made, then replayed in subsequent test runs. This makes your tests fast, deterministic, and independent of external services.
##
## Inspired by Ruby's excellent [VCR gem](https://github.com/vcr/vcr). `roc-vcr` brings a similar approach to Roc.
import http.Header exposing [Header]
import http.Method exposing [Method]
import http.Request exposing [Request]
import http.Response exposing [Response]
import base64.Base64

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
	## `redact`: more names whose values are kept out of the cassette, on top
	## of the ones that always are. Defaults to `[]`.
	##
	## `keep`: names that end like a secret but hold none, whose values stay
	## in the cassette, such as a token that pages through results under a
	## name the rule below misses. Defaults to `[]`.
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
	## These never reach a cassette, with no config needed:
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
	## A token that pages through results is no secret, so it stays: a name
	## that ends in `token` and has `page`, `next`, `continuation`, `sync` or
	## `cursor` in it, as `pageToken`, `NextToken` and `continuationToken` do.
	## So does every name in `keep` that `redact` does not have. Hidden, a
	## paging token would make the requests for the pages after the first all
	## look the same, and a replay would answer each of them with the second
	## page.
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
		redact : List(Str) ?? [],
		keep : List(Str) ?? [],
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
		filters = filters_from({ redact: config.redact, keep: config.keep }, config.remove_headers, config.replace_sensitive_data)
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
	names : Names,
	remove_headers : List(Str),
	replace_sensitive_data : List({ find : Str, replace : Str }),
}

## The names of a config that change which values [is_secret_name] hides:
## `redact` adds names, and `keep` takes out names that end like a secret
Names : {
	redact : List(Str),
	keep : List(Str),
}

## The filters of a config, with the names [normalized] and the headers to
## remove in lower case
filters_from : Names, List(Str), List({ find : Str, replace : Str }) -> Filters
filters_from = |{ redact, keep }, remove_headers, replace_sensitive_data| {
	names: {
		redact: redact.map(|name| normalized(name.to_utf8())),
		keep: keep.map(|name| normalized(name.to_utf8())),
	},
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
clean_text = |text, filters| replace_data(scrub(text, filters.names), filters)

## `text` with what `replace_sensitive_data` finds replaced
replace_data : Str, Filters -> Str
replace_data = |text, filters|
	filters.replace_sensitive_data.fold(text, |acc, { find, replace }| acc.replace_each(find, replace))

## Drop the removed headers, in any case, and scrub the values of the rest
clean_headers : List(Header), Filters -> List(Header)
clean_headers = |headers, filters|
	headers
		.keep_if(|header| !(filters.remove_headers.contains(header.name.with_ascii_lowercased())))
		.map(|header| { name: header.name, value: replace_data(scrub_header(header.name, header.value, filters.names), filters) })

## Clean a body. A body that is not UTF-8 is left as it is.
clean_body : List(U8), Filters -> List(U8)
clean_body = |bytes, filters|
	match Str.from_utf8(bytes) {
		Ok(text) => Str.to_utf8(clean_text(text, filters))
		Err(_) => bytes
	}

# Scrubbing secrets

## What replaces the user and password of a URL and the credentials of a
## request
credentials : Str
credentials = "<CREDENTIALS>"

## What replaces a cookie that has no name
nameless_cookie : Str
nameless_cookie = "<COOKIE>"

## What replaces the value of `name`: the name in upper case, as in
## `<ACCESS_TOKEN>`
placeholder : Str -> Str
placeholder = |name| "<${name.with_ascii_uppercased()}>"

## `name` in lower case and without `_` and `-`, so that `access_token`,
## `Access-Token` and `accessToken` are one name
normalized : List(U8) -> Str
normalized = |name|
	Str.from_utf8_lossy(
		name
			.keep_if(|byte| byte != '_' and byte != '-')
			.map(|byte| if byte >= 'A' and byte <= 'Z' byte + 32 else byte),
	)

## How the [normalized] name of a secret ends
secret_endings : List(Str)
secret_endings = ["token", "secret", "password", "passwd", "pwd", "apikey", "privatekey", "accesskey", "secretkey"]

## What the [normalized] name of a token that pages through results has in
## it, next to the `token` it ends in
paging_words : List(Str)
paging_words = ["page", "next", "continuation", "sync", "cursor"]

## Whether the [normalized] name `key` is that of a token that pages through
## results, as `pageToken`, `NextToken` and `continuationToken` are. Such a
## token is no secret, and hidden, the requests for every page after the
## first would look the same.
is_paging_token : Str -> Bool
is_paging_token = |key| key.ends_with("token") and paging_words.any(|word| key.contains(word))

## Whether the [normalized] name `key` holds a secret: `redact` has it, or it
## ends in one of the [secret_endings] and is neither a paging token nor in
## `keep`
is_secret_name : Str, Names -> Bool
is_secret_name = |key, names|
	names.redact.contains(key) or (secret_endings.any(|ending| key.ends_with(ending)) and !is_paging_token(key) and !names.keep.contains(key))

## The value of the header `name` with its secrets replaced. `Authorization`
## keeps its scheme, as in `Bearer <CREDENTIALS>`, and a cookie header keeps
## the name of every cookie, as in `session=<SESSION>`. A header whose own
## name holds a secret loses its whole value, and any other is [scrub]bed.
scrub_header : Str, Str, Names -> Str
scrub_header = |name, value, names| {
	key = normalized(name.to_utf8())
	if value.is_empty() {
		value
	} else if key == "authorization" or key == "proxyauthorization" {
		match value.trim().split_first(" ") {
			Ok({ before, after }) if !after.trim().is_empty() => "${before} ${credentials}"
			_ => credentials
		}
	} else if key == "cookie" {
		Str.join_with(value.split_on(";").map(hide_cookie), ";")
	} else if key == "setcookie" {
		# Only the first part is the cookie, the rest are its attributes
		match value.split_first(";") {
			Ok({ before, after }) => "${hide_cookie(before)};${after}"
			Err(NotFound) => hide_cookie(value)
		}
	} else if is_secret_name(key, names) {
		placeholder(name)
	} else {
		scrub(value, names)
	}
}

## One cookie, `name=value`, with its value replaced by its name in upper
## case. An empty one is left as it is.
hide_cookie : Str -> Str
hide_cookie = |part|
	match part.split_first("=") {
		Ok({ before, after }) =>
			if after.trim().is_empty() {
				part
			} else {
				"${before}=${placeholder(before.trim())}"
			}
		Err(NotFound) =>
			if part.trim().is_empty() {
				part
			} else if part.starts_with(" ") {
				" ${nameless_cookie}"
			} else {
				nameless_cookie
			}
	}

## `text` with every secret in it replaced: the user and password of a URL,
## the token after `Bearer`, and the value of every name that
## [is_secret_name]. One pass, so a big body takes no longer than it has to.
scrub : Str, Names -> Str
scrub = |text, names| {
	bytes = text.to_utf8()
	len = bytes.len()
	var $out = []
	var $copied = 0
	var $i = 0
	while $i < len {
		match secret_at(bytes, $i, names) {
			Found({ start, end, replacement }) => {
				$out = $out.concat(bytes.sublist({ start: $copied, len: start - $copied })).concat(replacement)
				$copied = end
				$i = end
			}
			Next(next) => {
				$i = next
			}
		}
	}
	if $copied == 0 {
		text
	} else {
		# Only ASCII was spliced in, at ASCII boundaries
		Str.from_utf8_lossy($out.concat(bytes.sublist({ start: $copied, len: len - $copied })))
	}
}

## A secret in some text: the bytes from `start` to `end`, and what replaces
## them
Secret : { start : U64, end : U64, replacement : List(U8) }

## The secret that starts at `index`, or the index to look at next. A name
## is read whole, so every byte is looked at about once.
secret_at : List(U8), U64, Names -> [Found(Secret), Next(U64)]
secret_at = |bytes, index, names| {
	byte = bytes.get(index).ok_or(0)
	if byte == ':' {
		user_info_at(bytes, index)
	} else if is_name_byte(byte) and !(index > 0 and is_name_byte(bytes.get(index - 1).ok_or(0))) {
		name_end = token_end(bytes, index, |b| !is_name_byte(b))
		name = bytes.sublist({ start: index, len: name_end - index })
		key = normalized(name)
		found =
			if key == "bearer" {
				bearer_token(bytes, name_end)
			} else if is_secret_name(key, names) {
				value_of(bytes, index, name_end)
			} else {
				Err(NotFound)
			}
		match found {
			Ok(secret) => Found(secret)
			Err(NotFound) => Next(name_end)
		}
	} else {
		Next(index + 1)
	}
}

## The user and password of the URL whose `://` is at `index`, written
## `:\/\/` in JSON too. They run to the last `@` of the authority, as a URL
## parser reads them, so a password may hold an `@`.
user_info_at : List(U8), U64 -> [Found(Secret), Next(U64)]
user_info_at = |bytes, index| {
	start =
		if starts_with_at(bytes, index, "://") {
			Ok(index + 3)
		} else if starts_with_at(bytes, index, ":\\/\\/") {
			Ok(index + 5)
		} else {
			Err(NotAUrl)
		}
	match start {
		Ok(after) => {
			end = token_end(bytes, after, |byte| !is_authority_byte(byte))
			match last_index_of(bytes, '@', after, end) {
				Ok(at) if at > after => Found({ start: after, end: at, replacement: credentials.to_utf8() })
				_ => Next(after)
			}
		}
		Err(NotAUrl) => Next(index + 1)
	}
}

## The token after `Bearer` and a space, where `Bearer` ends at `name_end`
bearer_token : List(U8), U64 -> Try(Secret, [NotFound])
bearer_token = |bytes, name_end|
	if bytes.get(name_end) == Ok(' ') {
		start = skip_spaces(bytes, name_end)
		end = unquoted_end(bytes, start)
		if end > start Ok({ start, end, replacement: credentials.to_utf8() }) else Err(NotFound)
	} else {
		Err(NotFound)
	}

## The value of the secret name from `name_start` to `name_end`. A name
## counts where `=` follows it, and where `:` follows it in quotes, as in
## JSON, or at the start of a field, as in a `name: value` line. Blanks and
## the quote that closes the name may come in between. A quoted value is
## replaced inside its quotes, an object, a list, `null` and a Boolean are
## left, and any other value after a quoted name becomes a quoted
## placeholder, so JSON stays valid.
value_of : List(U8), U64, U64 -> Try(Secret, [NotFound])
value_of = |bytes, name_start, name_end| {
	name = Str.from_utf8_lossy(bytes.sublist({ start: name_start, len: name_end - name_start }))
	hidden = placeholder(name).to_utf8()
	quote = quote_before(bytes, name_start)
	quoted = !quote.is_empty() and bytes.sublist({ start: name_end, len: quote.len() }) == quote
	after_name = if quoted name_end + quote.len() else name_end
	separator_at = skip_spaces(bytes, after_name)
	separator = bytes.get(separator_at).ok_or(0)
	value_at = skip_spaces(bytes, separator_at + 1)
	separates = separator == '=' or (separator == ':' and (quoted or begins_field(bytes, name_start)))
	if !separates {
		Err(NotFound)
	} else {
		match quoted_value(bytes, value_at) {
			Ok({ start, end }) => if end > start Ok({ start, end, replacement: hidden }) else Err(NotFound)
			Err(Unquoted) => {
				end = unquoted_end(bytes, value_at)
				first = bytes.get(value_at).ok_or(0)
				value = bytes.sublist({ start: value_at, len: end - value_at })
				if end == value_at or first == '{' or first == '[' or ["null", "true", "false"].any(|word| value == word.to_utf8()) {
					Err(NotFound)
				} else if quoted and separator == ':' {
					Ok({ start: value_at, end, replacement: quote.concat(hidden).concat(quote) })
				} else {
					Ok({ start: value_at, end, replacement: hidden })
				}
			}
		}
	}
}

## The quote right before `index`, with the backslashes that escape it: `"`
## in JSON, `\"` in JSON inside a JSON string, and so on, or `'`. Empty when
## there is none.
quote_before : List(U8), U64 -> List(U8)
quote_before = |bytes, index| {
	before = if index == 0 0 else bytes.get(index - 1).ok_or(0)
	if before == '"' {
		List.repeat('\\', backslashes_before(bytes, index - 1, 0)).append('"')
	} else if before == '\'' {
		['\'']
	} else {
		[]
	}
}

## Where the content of the quoted value at `index` starts and ends. A value
## in `'` ends at the next `'` that no backslash escapes. A value in `"` may
## be escaped any number of times, as JSON inside JSON strings is, and the
## backslashes before its opening quote say how many.
quoted_value : List(U8), U64 -> Try({ start : U64, end : U64 }, [Unquoted])
quoted_value = |bytes, index| {
	level = token_end(bytes, index, |byte| byte != '\\') - index
	opening = bytes.get(index + level).ok_or(0)
	if opening == '"' {
		start = index + level + 1
		Ok({ start, end: closing_quote(bytes, '"', start, level) })
	} else if opening == '\'' and level == 0 {
		start = index + 1
		Ok({ start, end: closing_quote(bytes, '\'', start, 0) })
	} else {
		Err(Unquoted)
	}
}

## Where the content of a string from `start` ends: at the backslashes of
## the `quote` that closes it, or at the end of `bytes`. The string is
## escaped `level` times, so its closing quote has `level` backslashes before
## it. A quote inside it has more, and so does a backslash at its end, which
## escaping doubles at every level: a quote closes it when the backslashes
## before it are `level` and a multiple of `2 * (level + 1)` on top.
closing_quote : List(U8), U8, U64, U64 -> U64
closing_quote = |bytes, quote, start, level| {
	len = bytes.len()
	period = 2 * (level + 1)
	var $i = start
	var $end = len
	while $end == len and $i < len {
		if bytes.get($i) == Ok(quote) {
			slashes = backslashes_before(bytes, $i, start)
			if slashes >= level and (slashes - level) % period == 0 {
				$end = $i - level
			}
		}
		$i = $i + 1
	}
	$end
}

## How many backslashes come right before `index`, counting no further back
## than `floor`
backslashes_before : List(U8), U64, U64 -> U64
backslashes_before = |bytes, index, floor| {
	var $i = index
	while $i > floor and bytes.get($i - 1) == Ok('\\') {
		$i = $i - 1
	}
	index - $i
}

## Whether the name at `index` starts a field: only spaces stand between it
## and the start of the text, a line break, an opening bracket, `,` or `;`.
## That is where a `name: value` line or an object puts a name, while a
## sentence such as `invalid token: abc` does not.
begins_field : List(U8), U64 -> Bool
begins_field = |bytes, index| {
	var $i = index
	while $i > 0 and is_space(bytes.get($i - 1).ok_or(0)) {
		$i = $i - 1
	}
	$i == 0 or "\n\r{([,;".to_utf8().contains(bytes.get($i - 1).ok_or(0))
}

## Where an unquoted value from `start` ends: at a byte that
## [is_value_end]. A placeholder such as `<TOKEN>` is part of the value, so
## that a value scrubbed before, or made from one that was, as a signature
## computed from a replayed token is, is replaced whole.
unquoted_end : List(U8), U64 -> U64
unquoted_end = |bytes, start| {
	len = bytes.len()
	var $i = start
	var $done = Bool.False
	while !$done and $i < len {
		match placeholder_end(bytes, $i) {
			Ok(end) => {
				$i = end
			}
			Err(NotFound) =>
				if is_value_end(bytes.get($i).ok_or(0)) {
					$done = Bool.True
				} else {
					$i = $i + 1
				}
		}
	}
	$i
}

## The index after the placeholder that starts at `index`: `<`, upper case
## letters, digits and `_-.`, then `>`
placeholder_end : List(U8), U64 -> Try(U64, [NotFound])
placeholder_end = |bytes, index|
	if bytes.get(index) == Ok('<') {
		close = token_end(bytes, index + 1, |byte| !(is_name_byte(byte) and !(byte >= 'a' and byte <= 'z')))
		if close > index + 1 and bytes.get(close) == Ok('>') Ok(close + 1) else Err(NotFound)
	} else {
		Err(NotFound)
	}

## Whether `needle` is at `index` of `bytes`
starts_with_at : List(U8), U64, Str -> Bool
starts_with_at = |bytes, index, needle| {
	needle_bytes = needle.to_utf8()
	bytes.sublist({ start: index, len: needle_bytes.len() }) == needle_bytes
}

## The last `needle` in `bytes` from `start` up to `end`
last_index_of : List(U8), U8, U64, U64 -> Try(U64, [NotFound])
last_index_of = |bytes, needle, start, end| {
	var $found = Err(NotFound)
	var $i = start
	while $i < end {
		if bytes.get($i) == Ok(needle) {
			$found = Ok($i)
		}
		$i = $i + 1
	}
	$found
}

## Letters, digits and `_-.`, the bytes a name is made of
is_name_byte : U8 -> Bool
is_name_byte = |byte|
	(byte >= '0' and byte <= '9') or (byte >= 'A' and byte <= 'Z') or (byte >= 'a' and byte <= 'z') or byte == '_' or byte == '-' or byte == '.'

## Space or tab
is_space : U8 -> Bool
is_space = |byte| byte == ' ' or byte == '\t'

## What ends an unquoted value: a blank, a quote, a backslash, `<` or `>`,
## or one of `&,;#)]}`
is_value_end : U8 -> Bool
is_value_end = |byte|
	is_space(byte) or byte == '\n' or byte == '\r' or byte == '"' or byte == '\'' or byte == '\\' or byte == '<' or byte == '>' or byte == '&' or byte == ',' or byte == ';' or byte == '#' or byte == ')' or byte == ']' or byte == '}'

## What the authority of a URL is made of, per RFC 3986: letters, digits,
## any byte of a non-ASCII character, and `-._~%!$&'()*+,;=:@[]`. `<` and
## `>` count too, so a placeholder is found again. Anything else ends it, a
## `/`, `?`, `#`, `\`, blank or `"` included.
is_authority_byte : U8 -> Bool
is_authority_byte = |byte|
	(byte >= '0' and byte <= '9') or (byte >= 'A' and byte <= 'Z') or (byte >= 'a' and byte <= 'z') or byte >= 128 or "-._~%!$&'()*+,;=:@[]<>".to_utf8().contains(byte)

## The index after the spaces from `start`
skip_spaces : List(U8), U64 -> U64
skip_spaces = |bytes, start| token_end(bytes, start, |byte| !is_space(byte))

## The index of the first byte from `start` that satisfies `stop`, or the end
token_end : List(U8), U64, (U8 -> Bool) -> U64
token_end = |bytes, start, stop| {
	len = bytes.len()
	var $i = start
	while $i < len and !stop(bytes.get($i).ok_or(0)) {
		$i = $i + 1
	}
	$i
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
	# WORKAROUND: roc-lang/roc#11471. The parsed value comes here whole from
	# `decode_cassette`. Mapping its `interactions` field right where it is
	# parsed passes `roc check` and panics `roc test` and every build with
	# "checked generated codec contract was missing required method call
	# parse_record_field". Nothing to undo when fixed beyond this comment.
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

## The [Names] of a config with `redact` and `keep`
names_of : List(Str), List(Str) -> Names
names_of = |redact, keep| filters_from({ redact, keep }, [], []).names

## The [Names] of a config that names none
no_names : Names
no_names = names_of([], [])

## `text` scrubbed with the names in `redact` on top of the built-in ones
scrubbed : Str, List(Str) -> Str
scrubbed = |text, redact| scrub(text, names_of(redact, []))

## `text` as a JSON string, to put JSON inside JSON
json_string : Str -> Str
json_string = |text| "\"${text.replace_each("\\", "\\\\").replace_each("\"", "\\\"")}\""

test_request : Request
test_request =
	Request.from_method(POST)
		.with_uri("https://api.example.com/things?account=SECRET")
		.add_header("Authorization", "Bearer SECRET")
		.add_header("Accept", "application/json")
		.with_body(Str.to_utf8("{\"account\":\"SECRET\"}"))

test_filters : Filters
test_filters = filters_from({ redact: [], keep: [] }, ["accept"], [{ find: "SECRET", replace: "[REDACTED]" }])

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

# Headers
expect scrub_header("Authorization", "Bearer abc", no_names) == "Bearer <CREDENTIALS>"
expect scrub_header("proxy-authorization", "Basic dXNlcjpwdw==", no_names) == "Basic <CREDENTIALS>"
expect scrub_header("Authorization", "abc", no_names) == "<CREDENTIALS>"
expect scrub_header("Cookie", "session=abc; lang=en; theme=; flag", no_names) == "session=<SESSION>; lang=<LANG>; theme=; <COOKIE>"
expect scrub_header("Set-Cookie", "id=a3f; Path=/; Secure; HttpOnly", no_names) == "id=<ID>; Path=/; Secure; HttpOnly"
expect scrub_header("X-Api-Key", "abc", no_names) == "<X-API-KEY>"
expect scrub_header("X-Partner", "abc", names_of(["x-partner"], [])) == "<X-PARTNER>"
expect scrub_header("Link", "<https://g.com/x?access_token=abc>; rel=\"next\"", no_names) == "<https://g.com/x?access_token=<ACCESS_TOKEN>>; rel=\"next\""
expect scrub_header("Accept", "application/json", no_names) == "application/json"
expect scrub_header("Authorization", "", no_names) == ""

# Scrubbing a header again changes nothing more
expect
	[("Authorization", "Bearer abc"), ("Authorization", "abc"), ("Cookie", "a=1; b"), ("Set-Cookie", "id=1; Path=/"), ("X-Api-Key", "k")].all(
		|(name, value)| {
			once = scrub_header(name, value, no_names)
			scrub_header(name, once, no_names) == once
		},
	)

# Query parameters, by a built-in name and by one in `redact`
expect scrubbed("https://g.com/me?access_token=EAAb3&appsecret_proof=9f1&limit=5", ["appsecret_proof"]) == "https://g.com/me?access_token=<ACCESS_TOKEN>&appsecret_proof=<APPSECRET_PROOF>&limit=5"

# A name in any case, with or without `_` and `-`
expect scrubbed("Access-Token=a&API_KEY=b&apiKey=c&clientSecret=d", []) == "Access-Token=<ACCESS-TOKEN>&API_KEY=<API_KEY>&apiKey=<APIKEY>&clientSecret=<CLIENTSECRET>"

# JSON string fields, with blanks around the colon, escaped quotes inside and
# an escaped backslash at the end
expect scrubbed("{\"password\" : \"hunter2\", \"id\": \"1\"}", []) == "{\"password\" : \"<PASSWORD>\", \"id\": \"1\"}"
expect scrubbed("{\"token\":\"a\\\"b\",\"secret\":\"c\\\\\",\"id\":\"1\"}", []) == "{\"token\":\"<TOKEN>\",\"secret\":\"<SECRET>\",\"id\":\"1\"}"

# JSON inside a JSON string, and inside that
expect {
	inner = |token| "{\"access_token\":\"${token}\",\"id\":1}"
	scrubbed("{\"payload\":${json_string(inner("abc"))}}", []) == "{\"payload\":${json_string(inner("<ACCESS_TOKEN>"))}}"
}
expect {
	twice = |token| "{\"a\":${json_string("{\"b\":${json_string("{\"token\":\"${token}\"}")}}")}}"
	scrubbed(twice("abc"), []) == twice("<TOKEN>")
}

# A JSON number becomes a string, so the JSON stays valid, and Booleans, null,
# objects and lists are left, so a flag still decodes as one
expect scrubbed("{\"pin\": 4711, \"secret\": true, \"token\": null, \"password\": {\"old\": \"x\"}}", ["pin"]) == "{\"pin\": \"<PIN>\", \"secret\": true, \"token\": null, \"password\": {\"old\": \"x\"}}"
expect scrubbed("{\"has_password\":true,\"is_secret\":false}&secret=true", []) == "{\"has_password\":true,\"is_secret\":false}&secret=true"
expect scrubbed("{\"p\":${json_string("{\"pin\":4711}")}}", ["pin"]) == "{\"p\":${json_string("{\"pin\":\"<PIN>\"}")}}"

# `name: value` lines, but not a sentence that happens to hold a name
expect scrubbed("password: hunter2\ntoken: abc\nuser: bob", []) == "password: <PASSWORD>\ntoken: <TOKEN>\nuser: bob"
expect scrubbed("Invalid token: abc. The password is wrong", []) == "Invalid token: abc. The password is wrong"

# The user and password of a URL, in JSON's `\/` too, and not an address
# after the host
expect scrubbed("postgres://user:pw@db/app and https:\\/\\/u:p@h.se\\/x", []) == "postgres://<CREDENTIALS>@db/app and https:\\/\\/<CREDENTIALS>@h.se\\/x"
expect scrubbed("https://example.com/?email=a@b.com mailto:a@b.com", []) == "https://example.com/?email=a@b.com mailto:a@b.com"

# The token after `Bearer`, but not a token type
expect scrubbed("{\"token_type\":\"bearer\",\"auth\":\"Bearer abc.def-ghi\"}", []) == "{\"token_type\":\"bearer\",\"auth\":\"Bearer <CREDENTIALS>\"}"

# A value made from a placeholder, as a signature computed from a replayed
# token is, is replaced whole, and so is a placeholder in a URL in a Link
# header
expect scrubbed("appsecret_proof=proof-of-<ACCESS_TOKEN>&x=1", ["appsecret_proof"]) == "appsecret_proof=<APPSECRET_PROOF>&x=1"
expect scrubbed("<https://g.com/x?access_token=<ACCESS_TOKEN>>; rel=\"next\"", []) == "<https://g.com/x?access_token=<ACCESS_TOKEN>>; rel=\"next\""
expect scrubbed("token=abc<br>", []) == "token=<TOKEN><br>"

# A name inside a longer name is not the name
expect scrubbed("zipcode=1&code=2", ["code"]) == "zipcode=1&code=<CODE>"

# Empty values and names that hold no secret are left
expect scrubbed("token=&secret=\"\"&user=bob&page=2&token_type=x&monkey=1&author=Jane", []) == "token=&secret=\"\"&user=bob&page=2&token_type=x&monkey=1&author=Jane"

# A token that pages through results is left, so the requests for the pages
# after the first differ, while the access token next to it is not
expect {
	paging = "pageToken=a&next_page_token=b&NextToken=c&ContinuationToken=d&sync-token=e&cursorToken=f"
	scrubbed("${paging}&access_token=x", []) == "${paging}&access_token=<ACCESS_TOKEN>"
}
expect scrubbed("{\"items\":[],\"nextPageToken\":\"CAUQAA\"}", []) == "{\"items\":[],\"nextPageToken\":\"CAUQAA\"}"
expect scrub_header("X-Next-Page-Token", "CAUQAA", no_names) == "CAUQAA"

# A name in `keep` is left, found the way any name is
expect scrub("resume_token=a&Marker-Token=b&refresh_token=c", names_of([], ["resumeToken", "marker_token"])) == "resume_token=a&Marker-Token=b&refresh_token=<REFRESH_TOKEN>"
expect scrub_header("X-Resume-Token", "abc", names_of([], ["x_resume_token"])) == "abc"

# `redact` wins over `keep` and the paging rule, and `keep` leaves what is
# hidden by more than its name
expect scrub("page_token=a&x_token=b", names_of(["page_token", "x_token"], ["x_token"])) == "page_token=<PAGE_TOKEN>&x_token=<X_TOKEN>"
expect scrub_header("Authorization", "Bearer abc", names_of([], ["authorization"])) == "Bearer <CREDENTIALS>"
expect scrub("Bearer abc postgres://u:p@db", names_of([], ["bearer"])) == "Bearer <CREDENTIALS> postgres://<CREDENTIALS>@db"

# Scrubbing again changes nothing more
expect
	[
		"https://g.com/me?access_token=EAAb3&limit=5",
		"{\"password\" : \"hunter2\", \"token\": \"a\\\"b\"}",
		"{\"payload\":${json_string("{\"access_token\":\"abc\",\"pin\":4711}")}}",
		"{\"pin\": 4711, \"secret\": true}",
		"password: hunter2\ntoken: abc",
		"postgres://user:pw@db/app",
		"Bearer abc.def",
		"<https://g.com/x?access_token=abc>",
		"appsecret_proof=proof-of-<ACCESS_TOKEN>",
	].all(
		|text| {
			once = scrubbed(text, ["pin"])
			scrubbed(once, ["pin"]) == once
		},
	)

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
