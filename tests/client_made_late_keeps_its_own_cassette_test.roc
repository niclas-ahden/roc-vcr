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

before_paying : Str
before_paying = "client_made_late_before_paying"

after_paying : Str
after_paying = "client_made_late_after_paying"

invoice : Str
invoice = "https://api.test.com/invoices/42"

## A server that answers every request with its method and the invoice's
## `state`
server : Str -> (Request => Try(Response, [MockHttpError]))
server = |state| |request| Ok(Response.from_status(200).with_body(Str.to_utf8("${request.method_str()} ${state}")))

## The test the README describes: read an invoice, pay it, and read it again.
## The second read expects a new answer to the same request, so it gets a
## client and a cassette of its own, made only after the first client has
## recorded.
record! : Vcr.Mode => Try({}, _)
record! = |mode| {
	client! = Vcr.init!({ ..Support.config(mode), http_send!: server("unpaid") }, before_paying)?
	_ = client!(Support.request(GET, invoice))?
	_ = client!(Support.request(POST, "${invoice}/pay"))?

	after_paying! = Vcr.init!({ ..Support.config(mode), http_send!: server("paid") }, after_paying)?
	_ = after_paying!(Support.request(GET, invoice))?
	Ok({})
}

## What a cassette holds, as `METHOD uri`
recorded! : Str => Try(List(Str), _)
recorded! = |name| {
	cassette = Support.load_cassette!(name)?
	Ok(cassette.interactions.map(|interaction| "${interaction.request.method_str()} ${interaction.request.uri()}"))
}

## The late client records into its own cassette in `Once` and `Replace`,
## and neither client touches the other's cassette.
main! : List(OsStr) => Try({}, _)
main! = |_args| {
	Support.reset!(before_paying)?
	Support.reset!(after_paying)?

	# A first run, with no cassettes yet
	record!(Once)?
	Assert.eq(recorded!(before_paying)?, ["GET ${invoice}", "POST ${invoice}/pay"])?
	Assert.eq(recorded!(after_paying)?, ["GET ${invoice}"])?

	# Recording again over those cassettes. The late client deletes only its own.
	record!(Replace)?
	Assert.eq(recorded!(before_paying)?, ["GET ${invoice}", "POST ${invoice}/pay"])?
	Assert.eq(recorded!(after_paying)?, ["GET ${invoice}"])?

	# Replaying, the same request gets the answer of its own cassette
	client! = Vcr.init!(Support.replay_config, before_paying)?
	after_paying! = Vcr.init!(Support.replay_config, after_paying)?
	Assert.eq(Str.from_utf8_lossy(client!(Support.request(GET, invoice))?.body()), "GET unpaid")?
	Assert.eq(Str.from_utf8_lossy(after_paying!(Support.request(GET, invoice))?.body()), "GET paid")
}
