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
cassette_name = "replace_deletes_existing_cassette"

## `Replace` starts from an empty cassette, then records like `Once` does.
main! : List(OsStr) => Try({}, _)
main! = |_args| {
	Support.reset!(cassette_name)?

	old! = Vcr.init!(Support.config(Once), cassette_name)?
	_ = old!(Support.request(GET, "https://api.test.com/old"))?

	new! = Vcr.init!(Support.config(Replace), cassette_name)?
	_ = new!(Support.request(GET, "https://api.test.com/new-1"))?
	_ = new!(Support.request(GET, "https://api.test.com/new-2"))?

	cassette = Support.load_cassette!(cassette_name)?
	Assert.eq(
		cassette.interactions.map(|interaction| interaction.request.uri()),
		["https://api.test.com/new-1", "https://api.test.com/new-2"],
	)
}
