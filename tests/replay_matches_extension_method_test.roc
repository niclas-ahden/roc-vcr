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

cassette_name : Str
cassette_name = "replay_matches_extension_method"

## A method outside the standard ones is stored under its own name and found
## again when replaying.
main! : List(OsStr) => Try({}, _)
main! = |_args| {
	Support.reset!(cassette_name)?
	request = Support.request(Unknown("PURGE"), "https://api.test.com/cache")

	record! = Vcr.init!(Support.config(Once), cassette_name)?
	recorded = record!(request)?

	cassette = Support.load_cassette!(cassette_name)?
	Assert.eq(cassette.interactions.map(|interaction| interaction.request.method_str()), ["PURGE"])?

	replay! = Vcr.init!(Support.replay_config, cassette_name)?
	replayed = replay!(request)?
	Assert.eq(Support.fields(replayed), Support.fields(recorded))
}
