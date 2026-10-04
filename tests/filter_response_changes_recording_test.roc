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
cassette_name = "filter_response_changes_recording"

## `filter_response` changes what is recorded, not what the caller gets.
main! : List(OsStr) => Try({}, _)
main! = |_args| {
	Support.reset!(cassette_name)?
	config = { ..Support.config(Once), filter_response: |response| response.with_status(418) }
	client! = Vcr.init!(config, cassette_name)?

	response = client!(Support.request(GET, "https://api.test.com/filter"))?
	Assert.eq(response.status(), 200)?

	cassette = Support.load_cassette!(cassette_name)?
	Assert.eq(cassette.interactions.map(|interaction| interaction.response.status()), [418])
}
