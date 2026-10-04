app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.28.0/AP9SGT1yrhCKcFxKcoA5tBkNCM6ibBjBxcQGMTb6krev.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/2.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	spec: "https://github.com/niclas-ahden/roc-spec/releases/download/0.6.0/9ThTkhd7zrviwQpM3LvGd7pvzGhr4ZXNmWJV7pTJc9AJ.tar.zst",
	vcr: "../package/main.roc",
}

import pf.OsStr
import spec.Assert
import vcr.Vcr
import Support

cassette_name : Str
cassette_name = "replay_matches_by_body"

main! : List(OsStr) => Try({}, _)
main! = |_args| {
	Support.reset!(cassette_name)?
	base = Support.request(POST, "https://api.test.com/data")
	request_a = base.with_body(Str.to_utf8("body-A"))
	request_b = base.with_body(Str.to_utf8("body-B"))

	record! = Vcr.init!(Support.config(Once), cassette_name)?
	_ = record!(request_a)?
	_ = record!(request_b)?

	replay! = Vcr.init!(Support.replay_config, cassette_name)?
	response = replay!(request_b)?

	Assert.contains(Str.from_utf8_lossy(response.body()), "body=body-B")
}
