app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.28.0/AP9SGT1yrhCKcFxKcoA5tBkNCM6ibBjBxcQGMTb6krev.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/2.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	spec: "https://github.com/niclas-ahden/roc-spec/releases/download/0.6.0/9ThTkhd7zrviwQpM3LvGd7pvzGhr4ZXNmWJV7pTJc9AJ.tar.zst",
	vcr: "../package/main.roc",
}

import pf.OsStr
import spec.Assert
import vcr.Vcr
import http.Response
import Support

cassette_name : Str
cassette_name = "record_binary_body"

## A body that is not UTF-8 is stored as base64 and replayed byte for byte.
main! : List(OsStr) => Try({}, _)
main! = |_args| {
	Support.reset!(cassette_name)?
	png = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0xff, 0x00]
	request = Support.request(GET, "https://api.test.com/logo.png")

	send! = |_req| Ok(Response.from_status(200).with_body(png))
	record! = Vcr.init!({ ..Support.config(Once), http_send!: send! }, cassette_name)?
	Assert.eq(record!(request)?.body(), png)?

	json = Support.read_cassette!(cassette_name)?
	Assert.contains(json, "\"body_base64\": \"iVBORw0KGgr/AA==\"")?

	replay! = Vcr.init!(Support.replay_config, cassette_name)?
	Assert.eq(replay!(request)?.body(), png)
}
