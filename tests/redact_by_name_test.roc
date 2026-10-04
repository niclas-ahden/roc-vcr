app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.28.0/AP9SGT1yrhCKcFxKcoA5tBkNCM6ibBjBxcQGMTb6krev.tar.zst",
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
cassette_name = "redact_by_name"

## A graph API in the style of Meta's: the user token gets a page token, and
## the page token, with a proof computed from it, gets the insights. The page
## token comes back in a body, and again inside a paging URL.
graph_send! : Request => Try(Response, [MockHttpError])
graph_send! = |req| {
	body =
		if req.uri().starts_with("https://graph.test/me/accounts") {
			"{\"data\":[{\"access_token\":\"PAGE_TOKEN\",\"id\":\"1\"}],\"paging\":{\"next\":\"https:\\/\\/graph.test\\/me\\/accounts?access_token=PAGE_TOKEN&after=x\"}}"
		} else {
			"{\"impressions\":42}"
		}
	Ok(Response.from_status(200).with_body(Str.to_utf8(body)))
}

## Ask for the insights the way the code under test would
insights! = |client!, user_token| {
	accounts = client!(Support.request(GET, "https://graph.test/me/accounts?access_token=${user_token}"))?
	after_field = Str.from_utf8_lossy(accounts.body()).split_first("\"access_token\":\"") ? |_| NoPageToken
	page_token = after_field.after.split_first("\"") ? |_| NoPageToken
	proof = "proof-of-${page_token.before}"
	client!(Support.request(GET, "https://graph.test/1/insights?access_token=${page_token.before}&appsecret_proof=${proof}"))
}

## Values redacted by name stay out of the cassette wherever they are, the
## page token the test only learns while it runs included. A replay with other
## credentials matches, so it needs no real ones.
main! : List(OsStr) => Try({}, _)
main! = |_args| {
	Support.reset!(cassette_name)?
	# `access_token` is kept out whatever the config says, and the proof by name
	redact = ["appsecret_proof"]

	record! = Vcr.init!({ ..Support.config(Once), http_send!: graph_send!, redact }, cassette_name)?
	recorded = insights!(record!, "USER_TOKEN")?

	json = Support.read_cassette!(cassette_name)?
	Assert.not_contains(json, "USER_TOKEN")?
	Assert.not_contains(json, "PAGE_TOKEN")?
	Assert.not_contains(json, "proof-of-")?
	Assert.contains(json, "access_token=<ACCESS_TOKEN>&appsecret_proof=<APPSECRET_PROOF>")?

	replay! = Vcr.init!({ ..Support.replay_config, redact }, cassette_name)?
	replayed = insights!(replay!, "SOME_OTHER_TOKEN")?
	Assert.eq(Support.fields(replayed), Support.fields(recorded))
}
