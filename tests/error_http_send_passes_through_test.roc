app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.26.0/EuuihZ91yAY1ANck1QytRBcW2jexEfH6yVmxcPCHEHDz.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/2.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	spec: "https://github.com/niclas-ahden/roc-spec/releases/download/0.6.0/9ThTkhd7zrviwQpM3LvGd7pvzGhr4ZXNmWJV7pTJc9AJ.tar.zst",
	vcr: "../package/main.roc",
}

import pf.OsStr
import spec.Assert
import vcr.Vcr
import Support

cassette_name : Str
cassette_name = "error_http_send_passes_through"

## An error from `http_send!` reaches the caller as it is, and a failed
## request records nothing.
main! : List(OsStr) => Try({}, _)
main! = |_args| {
	Support.reset!(cassette_name)?
	config = { ..Support.config(Once), http_send!: |_request| Err(ConnectionRefused) }
	client! = Vcr.init!(config, cassette_name)?

	match client!(Support.request(GET, "https://api.test.com/")) {
		Err(ConnectionRefused) => {}
		other => return Err(ExpectedConnectionRefused(Str.inspect(other)))
	}

	match Support.read_cassette!(cassette_name) {
		Err(_) => Ok({})
		Ok(json) => Err(ExpectedNoCassette(json))
	}
}
