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
cassette_name = "replay_ignores_headers"

## Headers are not part of the request key unless `match_headers` names them.
main! : List(OsStr) => Try({}, _)
main! = |_args| {
	Support.reset!(cassette_name)?
	base = Support.request(GET, "https://api.test.com/headers")

	record! = Vcr.init!(Support.config(Once), cassette_name)?
	recorded = record!(base.add_header("X-Request-Id", "first-run"))?

	replay! = Vcr.init!(Support.replay_config, cassette_name)?
	replayed = replay!(base.add_header("X-Request-Id", "second-run"))?

	Assert.eq(Support.fields(replayed), Support.fields(recorded))
}
