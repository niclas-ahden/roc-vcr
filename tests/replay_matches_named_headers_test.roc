app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.28.0/AP9SGT1yrhCKcFxKcoA5tBkNCM6ibBjBxcQGMTb6krev.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/2.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	spec: "https://github.com/niclas-ahden/roc-spec/releases/download/0.6.0/9ThTkhd7zrviwQpM3LvGd7pvzGhr4ZXNmWJV7pTJc9AJ.tar.zst",
	vcr: "../package/main.roc",
}

import pf.OsStr
import spec.Assert
import vcr.Vcr
import Support

cassette_name : Str
cassette_name = "replay_matches_named_headers"

## A header in `match_headers` has to match, in any case, and the others do
## not count. Values are compared after the filters, so `Authorization`
## matches on its scheme whatever the credentials.
main! : List(OsStr) => Try({}, _)
main! = |_args| {
	Support.reset!(cassette_name)?
	base = Support.request(GET, "https://api.test.com/versioned")

	record! = Vcr.init!(Support.config(Once), cassette_name)?
	recorded = record!(
		base
			.add_header("Api-Version", "2024-01")
			.add_header("Authorization", "Bearer recording-token")
			.add_header("X-Request-Id", "first-run"),
	)?

	replay! = Vcr.init!({ ..Support.replay_config, match_headers: ["API-VERSION", "authorization"] }, cassette_name)?
	replayed = replay!(
		base
			.add_header("api-version", "2024-01")
			.add_header("Authorization", "Bearer replay-token")
			.add_header("X-Request-Id", "second-run"),
	)?
	Assert.eq(Support.fields(replayed), Support.fields(recorded))?

	match replay!(base.add_header("Api-Version", "2025-01").add_header("Authorization", "Bearer replay-token")) {
		Err(InteractionNotFound(message)) => Assert.contains(message, "whose api-version header differs: recorded \"2024-01\", sent \"2025-01\"")?
		other => return Err(ExpectedInteractionNotFound(Str.inspect(other)))
	}

	match replay!(base.add_header("Api-Version", "2024-01").add_header("Authorization", "Basic replay-token")) {
		Err(InteractionNotFound(message)) => Assert.contains(message, "whose authorization header differs: recorded \"Bearer <CREDENTIALS>\", sent \"Basic <CREDENTIALS>\"")
		other => Err(ExpectedInteractionNotFound(Str.inspect(other)))
	}
}
