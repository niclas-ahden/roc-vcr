## Finds the secrets in a piece of text or the value of a header, and
## replaces them. Internal to the package: [Vcr] runs it on everything it
## records and on every request it matches.
##
## Scrubbing finds every secret first, each with the name it was found by,
## and then [replace_secrets] replaces the ones `dont_redact` does not name.
Scrub := [].{

	## The names of a config that change what is redacted, [normalized]:
	## `redact` adds names to the ones [is_secret_name] finds, and
	## `dont_redact` names the secrets that stay, unless `redact` names them
	## too
	Names : {
		redact : List(Str),
		dont_redact : List(Str),
	}

	## The [Names] of a config's `redact` and `dont_redact`
	names_from : List(Str), List(Str) -> Names
	names_from = |redact, dont_redact| {
		redact: redact.map(|name| normalized(name.to_utf8())),
		dont_redact: dont_redact.map(|name| normalized(name.to_utf8())),
	}

	## `text` with every secret in it replaced, except the ones `dont_redact`
	## names
	text : Str, Names -> Str
	text = |text, names| replace_secrets(text, secrets_in(text.to_utf8(), names), names)

	## The value of the header `name` with its secrets replaced, except the
	## ones `dont_redact` names
	header : Str, Str, Names -> Str
	header = |name, value, names| replace_secrets(value, header_secrets(name, value, names), names)
}

## A secret in some text: the bytes from `start` to `end`, what replaces
## them, and the [normalized] name it was found by. The user and password of
## a URL have no name, so theirs is empty.
Secret : { start : U64, end : U64, replacement : List(U8), name : Str }

## `text` with its `secrets` replaced, except the ones [is_kept]. The secrets
## are in order and do not overlap. One that is kept stays as it is, with
## nothing inside it replaced.
replace_secrets : Str, List(Secret), Scrub.Names -> Str
replace_secrets = |text, secrets, names| {
	replaced = secrets.keep_if(|secret| !is_kept(secret.name, names))
	if replaced.is_empty() {
		text
	} else {
		bytes = text.to_utf8()
		var $out = []
		var $copied = 0
		for secret in replaced {
			$out = $out.concat(bytes.sublist({ start: $copied, len: secret.start - $copied })).concat(secret.replacement)
			$copied = secret.end
		}
		# Every secret starts and ends on a character boundary
		Str.from_utf8_lossy($out.concat(bytes.sublist({ start: $copied, len: bytes.len() - $copied })))
	}
}

## Whether `dont_redact` has the [normalized] name a secret was found by and
## `redact` does not. A secret with no name is never kept.
is_kept : Str, Scrub.Names -> Bool
is_kept = |name, names| !name.is_empty() and names.dont_redact.contains(name) and !names.redact.contains(name)

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
## ends in one of the [secret_endings] and is not a paging token
is_secret_name : Str, Scrub.Names -> Bool
is_secret_name = |key, names|
	names.redact.contains(key) or (secret_endings.any(|ending| key.ends_with(ending)) and !is_paging_token(key))

## The secrets in the value of the header `name`. `Authorization` hides its
## credentials and keeps its scheme, as in `Bearer <CREDENTIALS>`, and a
## cookie header hides the value of every cookie and keeps its name, as in
## `session=<SESSION>`. A header whose own name holds a secret hides its
## whole value, and any other has the [secrets_in] its value.
header_secrets : Str, Str, Scrub.Names -> List(Secret)
header_secrets = |name, value, names| {
	key = normalized(name.to_utf8())
	bytes = value.to_utf8()
	whole = |replacement| [{ start: 0, end: bytes.len(), replacement: replacement.to_utf8(), name: key }]
	if value.is_empty() {
		[]
	} else if key == "authorization" or key == "proxyauthorization" {
		match value.trim().split_first(" ") {
			Ok({ before, after }) if !after.trim().is_empty() => whole("${before} ${credentials}")
			_ => whole(credentials)
		}
	} else if key == "cookie" {
		cookie_secrets(bytes, bytes.len())
	} else if key == "setcookie" {
		# Only the first part is the cookie, the rest are its attributes
		cookie_secrets(bytes, token_end(bytes, 0, |byte| byte == ';'))
	} else if is_secret_name(key, names) {
		whole(placeholder(name))
	} else {
		secrets_in(bytes, names)
	}
}

## The value of every cookie in `bytes` up to `end`, where cookies are
## separated by `;`
cookie_secrets : List(U8), U64 -> List(Secret)
cookie_secrets = |bytes, end| {
	var $secrets = []
	var $start = 0
	while $start <= end {
		part_end = token_end(bytes, $start, |byte| byte == ';')
		$secrets = $secrets.concat(cookie_secret(bytes, $start, part_end))
		$start = part_end + 1
	}
	$secrets
}

## The value of the cookie from `start` to `end`, `name=value`, found by its
## name and replaced by it in upper case. A cookie with no name is found by
## none and becomes `<COOKIE>`. An empty one has no secret.
cookie_secret : List(U8), U64, U64 -> List(Secret)
cookie_secret = |bytes, start, end| {
	text = |from, to| Str.from_utf8_lossy(bytes.sublist({ start: from, len: to - from }))
	equals = token_end(bytes, start, |byte| byte == '=')
	if equals < end {
		cookie_name = text(start, equals).trim()
		if text(equals + 1, end).trim().is_empty() {
			[]
		} else {
			[{ start: equals + 1, end, replacement: placeholder(cookie_name).to_utf8(), name: normalized(cookie_name.to_utf8()) }]
		}
	} else if text(start, end).trim().is_empty() {
		[]
	} else {
		# The blank after the `;` before it stays
		hidden = if bytes.get(start) == Ok(' ') start + 1 else start
		[{ start: hidden, end, replacement: nameless_cookie.to_utf8(), name: "" }]
	}
}

## The secrets in `bytes`, in order: the user and password of a URL, the
## token after `Bearer`, and the value of every name that [is_secret_name].
## One pass, so a big body takes no longer than it has to.
secrets_in : List(U8), Scrub.Names -> List(Secret)
secrets_in = |bytes, names| {
	len = bytes.len()
	var $secrets = []
	var $i = 0
	while $i < len {
		match secret_at(bytes, $i, names) {
			Found(secret) => {
				$secrets = $secrets.append(secret)
				$i = secret.end
			}
			Next(next) => {
				$i = next
			}
		}
	}
	$secrets
}

## The secret that starts at `index`, or the index to look at next. A name
## is read whole, so every byte is looked at about once.
secret_at : List(U8), U64, Scrub.Names -> [Found(Secret), Next(U64)]
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
			Ok({ start, end, replacement }) => Found({ start, end, replacement, name: key })
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
				Ok(at) if at > after => Found({ start: after, end: at, replacement: credentials.to_utf8(), name: "" })
				_ => Next(after)
			}
		}
		Err(NotAUrl) => Next(index + 1)
	}
}

## The token after `Bearer` and a space, where `Bearer` ends at `name_end`
bearer_token : List(U8), U64 -> Try({ start : U64, end : U64, replacement : List(U8) }, [NotFound])
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
value_of : List(U8), U64, U64 -> Try({ start : U64, end : U64, replacement : List(U8) }, [NotFound])
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

# Tests, run with roc test package/main.roc

## The [Scrub.Names] of a config that names none
no_names : Scrub.Names
no_names = Scrub.names_from([], [])

## `text` scrubbed with the names in `redact` on top of the built-in ones
scrubbed : Str, List(Str) -> Str
scrubbed = |text, redact| Scrub.text(text, Scrub.names_from(redact, []))

## `text` as a JSON string, to put JSON inside JSON
json_string : Str -> Str
json_string = |text| "\"${text.replace_each("\\", "\\\\").replace_each("\"", "\\\"")}\""

# Headers
expect Scrub.header("Authorization", "Bearer abc", no_names) == "Bearer <CREDENTIALS>"
expect Scrub.header("proxy-authorization", "Basic dXNlcjpwdw==", no_names) == "Basic <CREDENTIALS>"
expect Scrub.header("Authorization", "abc", no_names) == "<CREDENTIALS>"
expect Scrub.header("Cookie", "session=abc; lang=en; theme=; flag", no_names) == "session=<SESSION>; lang=<LANG>; theme=; <COOKIE>"
expect Scrub.header("Set-Cookie", "id=a3f; Path=/; Secure; HttpOnly", no_names) == "id=<ID>; Path=/; Secure; HttpOnly"
expect Scrub.header("X-Api-Key", "abc", no_names) == "<X-API-KEY>"
expect Scrub.header("X-Partner", "abc", Scrub.names_from(["x-partner"], [])) == "<X-PARTNER>"
expect Scrub.header("Link", "<https://g.com/x?access_token=abc>; rel=\"next\"", no_names) == "<https://g.com/x?access_token=<ACCESS_TOKEN>>; rel=\"next\""
expect Scrub.header("Accept", "application/json", no_names) == "application/json"
expect Scrub.header("Authorization", "", no_names) == ""

# Scrubbing a header again changes nothing more
expect
	[("Authorization", "Bearer abc"), ("Authorization", "abc"), ("Cookie", "a=1; b"), ("Set-Cookie", "id=1; Path=/"), ("X-Api-Key", "k")].all(
		|(name, value)| {
			once = Scrub.header(name, value, no_names)
			Scrub.header(name, once, no_names) == once
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
expect Scrub.header("X-Next-Page-Token", "CAUQAA", no_names) == "CAUQAA"

# A name in `dont_redact` is left, found the way any name is
expect Scrub.text("resume_token=a&Marker-Token=b&refresh_token=c", Scrub.names_from([], ["resumeToken", "marker_token"])) == "resume_token=a&Marker-Token=b&refresh_token=<REFRESH_TOKEN>"
expect Scrub.header("X-Resume-Token", "abc", Scrub.names_from([], ["x_resume_token"])) == "abc"

# `redact` wins over the paging rule and over `dont_redact`, whichever rule
# found the secret
expect Scrub.text("page_token=a&x_token=b", Scrub.names_from(["page_token", "x_token"], ["x_token"])) == "page_token=<PAGE_TOKEN>&x_token=<X_TOKEN>"
expect Scrub.header("Authorization", "Bearer abc", Scrub.names_from(["authorization"], ["authorization"])) == "Bearer <CREDENTIALS>"
expect Scrub.header("Cookie", "lang=en", Scrub.names_from(["lang"], ["lang"])) == "lang=<LANG>"

# `dont_redact` takes out what any rule found, by the name it was found by
expect Scrub.header("Authorization", "Bearer abc", Scrub.names_from([], ["authorization"])) == "Bearer abc"
expect Scrub.header("Cookie", "session=abc; lang=en; flag", Scrub.names_from([], ["lang"])) == "session=<SESSION>; lang=en; <COOKIE>"
expect Scrub.header("Set-Cookie", "lang=en; Path=/", Scrub.names_from([], ["lang"])) == "lang=en; Path=/"
expect Scrub.text("Bearer abc postgres://u:p@db", Scrub.names_from([], ["bearer"])) == "Bearer abc postgres://<CREDENTIALS>@db"

# The user and password of a URL have no name, so no name keeps them
expect Scrub.text("postgres://u:p@db", Scrub.names_from([], ["", "_", "postgres"])) == "postgres://<CREDENTIALS>@db"

# A value that stays is left whole, and the secrets after it are still found
expect {
	inner = json_string("{\"password\":\"x\"}")
	text = "{\"sync_secret\":${inner},\"password\":\"y\"}"
	Scrub.text(text, Scrub.names_from([], ["sync_secret"])) == "{\"sync_secret\":${inner},\"password\":\"<PASSWORD>\"}"
}

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
