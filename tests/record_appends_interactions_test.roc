app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.26.0/EuuihZ91yAY1ANck1QytRBcW2jexEfH6yVmxcPCHEHDz.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/2.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	spec: "https://github.com/niclas-ahden/roc-spec/releases/download/0.6.0/9ThTkhd7zrviwQpM3LvGd7pvzGhr4ZXNmWJV7pTJc9AJ.tar.zst",
	vcr: "../package/main.roc",
}

import pf.OsStr exposing [OsStr]
import spec.Assert
import vcr.Vcr
import Support

cassette_name : Str
cassette_name = "record_appends_interactions"

## Every request is recorded, in order, a repeated one included.
main! : List(OsStr) => Try({}, _)
main! = |_args| {
	Support.reset!(cassette_name)?
	client! = Vcr.init!(Support.config(Once), cassette_name)?

	_ = client!(Support.request(GET, "https://api.test.com/1"))?
	_ = client!(Support.request(GET, "https://api.test.com/2"))?
	_ = client!(Support.request(GET, "https://api.test.com/2"))?

	cassette = Support.load_cassette!(cassette_name)?
	Assert.eq(
		cassette.interactions.map(|interaction| interaction.request.uri()),
		["https://api.test.com/1", "https://api.test.com/2", "https://api.test.com/2"],
	)
}
