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
cassette_name = "replay_matches_by_method"

main! : List(OsStr) => Try({}, _)
main! = |_args| {
	Support.reset!(cassette_name)?
	uri = "https://api.test.com/resource"

	record! = Vcr.init!(Support.config(Once), cassette_name)?
	_ = record!(Support.request(GET, uri))?
	_ = record!(Support.request(POST, uri))?

	replay! = Vcr.init!(Support.replay_config, cassette_name)?
	response = replay!(Support.request(POST, uri))?

	Assert.contains(Str.from_utf8_lossy(response.body()), "response-for:POST:")
}
