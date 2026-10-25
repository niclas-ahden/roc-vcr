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
