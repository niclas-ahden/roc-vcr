app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.26.0/EuuihZ91yAY1ANck1QytRBcW2jexEfH6yVmxcPCHEHDz.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/2.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	spec: "https://github.com/niclas-ahden/roc-spec/releases/download/0.6.0/9ThTkhd7zrviwQpM3LvGd7pvzGhr4ZXNmWJV7pTJc9AJ.tar.zst",
	vcr: "../package/main.roc",
}

import pf.OsStr
import spec.Assert
import vcr.Vcr
import Support

## tests/cassettes/recorded_before_scrubbing.json holds an API key and a
## password, as a version that kept less out would have recorded them. A
## replay scrubs the recorded requests the way it scrubs the one it gets, so
## the cassette still answers a request with other secrets, and keeps
## answering after a filter is added.
main! : List(OsStr) => Try({}, _)
main! = |_args| {
	client! = Vcr.init!({ ..Support.replay_config, cassette_dir: Support.fixture_dir }, "recorded_before_scrubbing")?
	request =
		Support.request(POST, "https://api.test.com/login?api_key=NEW_KEY")
			.with_body(Str.to_utf8("{\"user\":\"bob\",\"password\":\"new-password\"}"))

	response = client!(request)?
	Assert.eq(Str.from_utf8_lossy(response.body()), "logged in")
}
