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
cassette_name = "once_records_then_replays"

## `Once` records while there is no cassette, and replays once there is one.
main! : List(OsStr) => Try({}, _)
main! = |_args| {
	Support.reset!(cassette_name)?
	request = Support.request(GET, "https://api.test.com/once")

	first! = Vcr.init!(Support.config(Once), cassette_name)?
	recorded = first!(request)?

	# `no_http!` fails on any request, so this client can only be replaying
	second! = Vcr.init!({ ..Support.config(Once), http_send!: Support.no_http! }, cassette_name)?
	replayed = second!(request)?
	Assert.eq(Support.fields(replayed), Support.fields(recorded))?

	cassette = Support.load_cassette!(cassette_name)?
	Assert.eq(cassette.interactions.len(), 1)
}
