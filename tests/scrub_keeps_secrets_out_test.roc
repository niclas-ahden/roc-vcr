app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.26.0/EuuihZ91yAY1ANck1QytRBcW2jexEfH6yVmxcPCHEHDz.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/2.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	spec: "https://github.com/niclas-ahden/roc-spec/releases/download/0.6.0/9ThTkhd7zrviwQpM3LvGd7pvzGhr4ZXNmWJV7pTJc9AJ.tar.zst",
	vcr: "../package/main.roc",
}

import pf.OsStr
import http.Request
import http.Response
import spec.Assert
import vcr.Vcr
import Support

cassette_name : Str
cassette_name = "scrub_keeps_secrets_out"

## A login that hands out a token, a session cookie and a database URL
login_server! : Request => Try(Response, [MockHttpError])
login_server! = |_request|
	Ok(
		Response.from_status(200)
			.add_header("Set-Cookie", "session=SESSION_SECRET; Path=/; HttpOnly")
			.with_body(Str.to_utf8("{\"access_token\":\"ISSUED_SECRET\",\"expires_in\":3600,\"database\":\"postgres://app:DB_SECRET@db/app\"}")),
	)

## A request that carries `secret` everywhere a secret goes, a JSON string
## inside the body included
login : Str -> Request
login = |secret|
	Support.request(POST, "https://bob:${secret}@api.test.com/login?api_key=${secret}&page=1")
		.add_header("Authorization", "Bearer ${secret}")
		.add_header("Cookie", "session=${secret}; lang=en")
		.add_header("X-Api-Key", secret)
		.add_header("Accept", "application/json")
		.with_body(Str.to_utf8("{\"user\":\"bob\",\"password\":\"${secret}\",\"payload\":\"{\\\"token\\\":\\\"${secret}\\\"}\"}"))

## The headers of a request or response as pairs
pairs = |headers| headers.map(|header| (header.name, header.value))

## With no config for it, a cassette holds no credentials, cookie values,
## URL passwords, Bearer tokens or values of secret names. The caller gets
## the response as it came, and a replay with other secrets matches.
main! : List(OsStr) => Try({}, _)
main! = |_args| {
	Support.reset!(cassette_name)?

	record! = Vcr.init!({ ..Support.config(Once), http_send!: login_server! }, cassette_name)?
	response = record!(login("REQUEST_SECRET"))?
	Assert.contains(Str.from_utf8_lossy(response.body()), "ISSUED_SECRET")?

	json = Support.read_cassette!(cassette_name)?
	for secret in ["REQUEST_SECRET", "ISSUED_SECRET", "SESSION_SECRET", "DB_SECRET"] {
		Assert.not_contains(json, secret)?
	}

	cassette = Support.load_cassette!(cassette_name)?
	interaction = cassette.interactions.first() ? |_| NothingRecorded
	Assert.eq(interaction.request.uri(), "https://<CREDENTIALS>@api.test.com/login?api_key=<API_KEY>&page=1")?
	Assert.eq(
		pairs(interaction.request.headers()),
		[
			("Authorization", "Bearer <CREDENTIALS>"),
			("Cookie", "session=<SESSION>; lang=<LANG>"),
			("X-Api-Key", "<X-API-KEY>"),
			("Accept", "application/json"),
		],
	)?
	Assert.eq(Str.from_utf8_lossy(interaction.request.body()), "{\"user\":\"bob\",\"password\":\"<PASSWORD>\",\"payload\":\"{\\\"token\\\":\\\"<TOKEN>\\\"}\"}")?
	Assert.eq(pairs(interaction.response.headers()), [("Set-Cookie", "session=<SESSION>; Path=/; HttpOnly")])?
	Assert.eq(Str.from_utf8_lossy(interaction.response.body()), "{\"access_token\":\"<ACCESS_TOKEN>\",\"expires_in\":3600,\"database\":\"postgres://<CREDENTIALS>@db/app\"}")?

	replay! = Vcr.init!(Support.replay_config, cassette_name)?
	replayed = replay!(login("ANOTHER_SECRET"))?
	Assert.eq(Support.fields(replayed), Support.fields(interaction.response))
}
