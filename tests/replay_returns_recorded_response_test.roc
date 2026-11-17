app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.32.0/3MnQnCrtfe6XS5qx58MnAGU6iWk8i1N24MYfoejcWeax.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/2.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	spec: "https://github.com/niclas-ahden/roc-spec/releases/download/0.7.1/GXr8UJ7VDaJ8HYykmVYtTjLs7X4bZeE9YDTzAHoVXFJ9.tar.zst",
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
