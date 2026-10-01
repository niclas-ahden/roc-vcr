app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.26.0/EuuihZ91yAY1ANck1QytRBcW2jexEfH6yVmxcPCHEHDz.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/2.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	spec: "https://github.com/niclas-ahden/roc-spec/releases/download/0.6.0/9ThTkhd7zrviwQpM3LvGd7pvzGhr4ZXNmWJV7pTJc9AJ.tar.zst",
	vcr: "../package/main.roc",
}

import pf.Http
import pf.OsStr exposing [OsStr]
import http.Request exposing [Request]
import http.Response exposing [Response]
import spec.Assert
import vcr.Vcr
import Support

cassette_name : Str
cassette_name = "client_fits_where_http_send_does"

## The code under test, which takes its HTTP function as an argument and
## knows nothing of roc-vcr.
fetch_status! : (Request => Try(Response, err)), Str => Try(U16, err)
fetch_status! = |send!, uri| {
	response = send!(Request.from_method(GET).with_uri(uri))?
	Ok(response.status())
}

## How an app calls it. Never run, since no test touches the network, but
## checked, so basic-cli's `Http.send!` fits where the client does.
fetch_status_live! : Str => Try(U16, _)
fetch_status_live! = |uri| fetch_status!(Http.send!, uri)

## A client has the type of `http_send!`, so the same code runs with the real
## thing, with a client that records and with one that replays.
main! : List(OsStr) => Try({}, _)
main! = |_args| {
	Support.reset!(cassette_name)?
	uri = "https://api.test.com/status"

	live = fetch_status!(Support.http_send!, uri)?

	record! = Vcr.init!(Support.config(Once), cassette_name)?
	recorded = fetch_status!(record!, uri)?

	replay! = Vcr.init!(Support.replay_config, cassette_name)?
	replayed = fetch_status!(replay!, uri)?

	Assert.eq([live, recorded, replayed], [200, 200, 200])
}
