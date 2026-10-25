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
cassette_name = "replay_returns_recorded_response"

main! : List(OsStr) => Try({}, _)
main! = |_args| {
	Support.reset!(cassette_name)?
	request = Support.request(POST, "https://api.test.com/data").with_body(Str.to_utf8("payload"))

	record! = Vcr.init!(Support.config(Once), cassette_name)?
	recorded = record!(request)?

	# Replaying sends nothing: `replay_config` fails on any request
	replay! = Vcr.init!(Support.replay_config, cassette_name)?
	replayed = replay!(request)?

	Assert.eq(Support.fields(replayed), Support.fields(recorded))
}
