app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.30.0/6XAUy48Jp34GANurMrMf74DtF7NdpkhnqFLHE4gHNzJy.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/2.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	spec: "https://github.com/niclas-ahden/roc-spec/releases/download/0.7.0/BGjQKbG9U3V8cH6mRbypUAFVqFoVEu6n9bsA3QmFL1f4.tar.zst",
	vcr: "../package/main.roc",
}

import pf.OsStr
import spec.Assert
import vcr.Vcr
import Support

cassette_name : Str
cassette_name = "record_stores_request_and_response"

main! : List(OsStr) => Try({}, _)
main! = |_args| {
	Support.reset!(cassette_name)?
	client! = Vcr.init!(Support.config(Once), cassette_name)?

	response = client!(Support.request(GET, "https://api.test.com/users").add_header("Accept", "application/json"))?
	Assert.eq(response.status(), 200)?

	cassette = Support.load_cassette!(cassette_name)?
	Assert.eq(cassette.name, cassette_name)?
	interaction = match cassette.interactions {
		[only] => only
		other => return Err(ExpectedOneInteraction(other.len()))
	}
	Assert.eq(interaction.request.method_str(), "GET")?
	Assert.eq(interaction.request.uri(), "https://api.test.com/users")?
	Assert.eq(interaction.request.headers().map(|header| (header.name, header.value)), [("Accept", "application/json")])?
	Assert.eq(interaction.request.body(), [])?
	Assert.eq(Support.fields(interaction.response), Support.fields(response))
}
