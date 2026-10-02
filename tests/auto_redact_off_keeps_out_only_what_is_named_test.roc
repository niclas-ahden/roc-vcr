app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.26.0/EuuihZ91yAY1ANck1QytRBcW2jexEfH6yVmxcPCHEHDz.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/2.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	spec: "https://github.com/niclas-ahden/roc-spec/releases/download/0.6.0/9ThTkhd7zrviwQpM3LvGd7pvzGhr4ZXNmWJV7pTJc9AJ.tar.zst",
	vcr: "../package/main.roc",
}

import pf.OsStr
import http.Request
import http.Response
import spec.Assert
import vcr.Vcr
import Support

cassette_name : Str
cassette_name = "auto_redact_off_keeps_out_only_what_is_named"

## A login that hands out a token and a session id
login_server! : Request => Try(Response, [MockHttpError])
login_server! = |_request|
	Ok(Response.from_status(200).with_body(Str.to_utf8("{\"access_token\":\"ISSUED_TOKEN\",\"session_id\":\"SESSION_SECRET\"}")))

## A request with credentials the built-in rules would hide
login : Request
login =
	Support.request(POST, "https://bob:URL_PASSWORD@api.test.com/login?api_key=QUERY_KEY")
		.add_header("Authorization", "Bearer HEADER_TOKEN")

## With `auto_redact: Off`, the built-in rules hide nothing and only the
## names in `redact` are kept out. The caller gets the response as it came,
## and a replay with the same config matches the same request.
main! : List(OsStr) => Try({}, _)
main! = |_args| {
	Support.reset!(cassette_name)?

	record! = Vcr.init!({ ..Support.config(Once), http_send!: login_server!, auto_redact: Off, redact: ["session_id"] }, cassette_name)?
	recorded = record!(login)?
	Assert.contains(Str.from_utf8_lossy(recorded.body()), "SESSION_SECRET")?

	json = Support.read_cassette!(cassette_name)?
	for kept in ["URL_PASSWORD", "QUERY_KEY", "Bearer HEADER_TOKEN", "ISSUED_TOKEN"] {
		Assert.contains(json, kept)?
	}
	Assert.not_contains(json, "SESSION_SECRET")?
	Assert.contains(json, "<SESSION_ID>")?

	replay! = Vcr.init!({ ..Support.replay_config, auto_redact: Off, redact: ["session_id"] }, cassette_name)?
	replayed = replay!(login)?
	Assert.eq(Str.from_utf8_lossy(replayed.body()), "{\"access_token\":\"ISSUED_TOKEN\",\"session_id\":\"<SESSION_ID>\"}")
}
