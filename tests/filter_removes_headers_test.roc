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
cassette_name = "filter_removes_headers"

## Header names are matched whatever their case, in requests and responses.
main! : List(OsStr) => Try({}, _)
main! = |_args| {
	Support.reset!(cassette_name)?
	config = { ..Support.config(Once), remove_headers: ["authorization", "X-TRACE-ID", "x-mock"] }
	client! = Vcr.init!(config, cassette_name)?

	_ = client!(
		Support.request(GET, "https://api.test.com/secure")
			.add_header("Authorization", "secret")
			.add_header("X-Trace-Id", "trace-123")
			.add_header("Accept", "application/json"),
	)?

	cassette = Support.load_cassette!(cassette_name)?
	interaction = cassette.interactions.first() ? |_| NothingRecorded
	Assert.eq(interaction.request.headers().map(|header| (header.name, header.value)), [("Accept", "application/json")])?
	Assert.eq(interaction.response.headers().len(), 0)
}
