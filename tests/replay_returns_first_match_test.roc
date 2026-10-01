app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.26.0/EuuihZ91yAY1ANck1QytRBcW2jexEfH6yVmxcPCHEHDz.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/2.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	spec: "https://github.com/niclas-ahden/roc-spec/releases/download/0.6.0/9ThTkhd7zrviwQpM3LvGd7pvzGhr4ZXNmWJV7pTJc9AJ.tar.zst",
	vcr: "../package/main.roc",
}

import pf.OsStr exposing [OsStr]
import spec.Assert
import vcr.Vcr
import Support

## tests/cassettes/same_request_three_times.json holds the same GET three
## times, answered with status 201, 202 and 203, in the format 0.1.0 wrote.
## A client answers with the first match, however often it is asked, which is
## why a test that expects a new answer gives that part its own cassette.
main! : List(OsStr) => Try({}, _)
main! = |_args| {
	request = Support.request(GET, "https://api.test.com/same")
	client! = Vcr.init!({ ..Support.replay_config, cassette_dir: Support.fixture_dir }, "same_request_three_times")?

	Assert.eq(client!(request)?.status(), 201)?
	Assert.eq(client!(request)?.status(), 201)
}
