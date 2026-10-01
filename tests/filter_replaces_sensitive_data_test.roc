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
cassette_name = "filter_replaces_sensitive_data"

## The account number is replaced in the URI, the header values and both
## bodies of the recording. No name gives it away, so only
## `replace_sensitive_data` finds it. The mock echoes the request, which puts
## it in the response body as well.
main! : List(OsStr) => Try({}, _)
main! = |_args| {
	Support.reset!(cassette_name)?
	config = { ..Support.config(Once), replace_sensitive_data: [{ find: "4711", replace: "<ACCOUNT>" }] }
	client! = Vcr.init!(config, cassette_name)?

	response = client!(
		Support.request(POST, "https://api.test.com/accounts/4711?view=full")
			.add_header("X-Account", "4711")
			.with_body(Str.to_utf8("{\"account\":\"4711\"}")),
	)?

	# The caller gets the response as it came, only the recording is filtered
	Assert.contains(Str.from_utf8_lossy(response.body()), "4711")?

	json = Support.read_cassette!(cassette_name)?
	Assert.not_contains(json, "4711")?

	cassette = Support.load_cassette!(cassette_name)?
	interaction = cassette.interactions.first() ? |_| NothingRecorded
	Assert.eq(interaction.request.uri(), "https://api.test.com/accounts/<ACCOUNT>?view=full")?
	Assert.eq(interaction.request.headers().map(|header| (header.name, header.value)), [("X-Account", "<ACCOUNT>")])?
	Assert.eq(Str.from_utf8_lossy(interaction.request.body()), "{\"account\":\"<ACCOUNT>\"}")?
	Assert.contains(Str.from_utf8_lossy(interaction.response.body()), "accounts/<ACCOUNT>")
}
