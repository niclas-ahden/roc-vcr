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
