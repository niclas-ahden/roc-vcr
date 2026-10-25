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
cassette_name = "error_cassette_not_found"

## `init!` reports the missing cassette, before the code under test can
## handle the error or hide it.
main! : List(OsStr) => Try({}, _)
main! = |_args| {
	Support.reset!(cassette_name)?

	match Vcr.init!(Support.replay_config, cassette_name) {
		Err(CassetteNotFound(message)) => {
			Assert.contains(message, "tests/tmp/error_cassette_not_found.json")?
			Assert.contains(message, "Once or Replace")
		}
		Err(other) => Err(ExpectedCassetteNotFound(Str.inspect(other)))
		Ok(_) => Err(ExpectedCassetteNotFound("a client"))
	}
}
