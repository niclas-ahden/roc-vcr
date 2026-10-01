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

cassette_name : Str
cassette_name = "filter_request_applies_on_replay"

## `filter_request` changes a request on its way into the cassette and again
## before it is matched, so a request that differs only in what the filter
## takes away, a timestamp here, replays.
main! : List(OsStr) => Try({}, _)
main! = |_args| {
	Support.reset!(cassette_name)?
	without_timestamp = |request|
		match request.uri().split_first("&ts=") {
			Ok({ before, after: _ }) => request.with_uri(before)
			Err(_) => request
		}

	record! = Vcr.init!({ ..Support.config(Once), filter_request: without_timestamp }, cassette_name)?
	recorded = record!(Support.request(GET, "https://api.test.com/feed?page=1&ts=1000"))?

	replay! = Vcr.init!({ ..Support.replay_config, filter_request: without_timestamp }, cassette_name)?
	replayed = replay!(Support.request(GET, "https://api.test.com/feed?page=1&ts=2000"))?
	Assert.eq(Support.fields(replayed), Support.fields(recorded))?

	cassette = Support.load_cassette!(cassette_name)?
	Assert.eq(cassette.interactions.map(|interaction| interaction.request.uri()), ["https://api.test.com/feed?page=1"])
}
