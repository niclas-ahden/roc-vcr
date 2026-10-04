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

## tests/cassettes/same_request_three_times.json holds the same GET three
## times. The message for a miss names the cassette, what it has instead and
## how to record the request.
main! : List(OsStr) => Try({}, _)
main! = |_args| {
	config = { ..Support.replay_config, cassette_dir: Support.fixture_dir }

	unknown! = Vcr.init!(config, "same_request_three_times")?
	unknown =
		match unknown!(Support.request(GET, "https://api.test.com/not-recorded")) {
			Err(InteractionNotFound(message)) => message
			other => return Err(ExpectedInteractionNotFound(Str.inspect(other)))
		}
	Assert.contains(unknown, "tests/cassettes/same_request_three_times.json matches GET https://api.test.com/not-recorded.")?
	Assert.contains(unknown, "It has GET https://api.test.com/same, GET https://api.test.com/same, GET https://api.test.com/same.")?
	Assert.contains(unknown, "Run in Replace mode to record the cassette again.")?

	body! = Vcr.init!(config, "same_request_three_times")?
	match body!(Support.request(GET, "https://api.test.com/same").with_body(Str.to_utf8("{}"))) {
		Err(InteractionNotFound(message)) => Assert.contains(message, "whose body differs from byte 0: recorded the end of the body, sent \"{}\"")
		other => Err(ExpectedInteractionNotFound(Str.inspect(other)))
	}
}
