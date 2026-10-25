app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.30.0/6XAUy48Jp34GANurMrMf74DtF7NdpkhnqFLHE4gHNzJy.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/2.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	spec: "https://github.com/niclas-ahden/roc-spec/releases/download/0.7.0/BGjQKbG9U3V8cH6mRbypUAFVqFoVEu6n9bsA3QmFL1f4.tar.zst",
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
