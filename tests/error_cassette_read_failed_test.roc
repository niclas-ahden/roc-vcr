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
cassette_name = "error_cassette_read_failed"

## A cassette that is there but cannot be read is an error from `init!`, not
## reported as missing, and `Once` does not record over it.
main! : List(OsStr) => Try({}, _)
main! = |_args| {
	Support.reset!(cassette_name)?
	# A directory where the cassette should be exists, and cannot be read
	Support.cassette_dir.join("${cassette_name}.json").create_all!()?

	for mode in [Replay, Once] {
		match Vcr.init!({ ..Support.config(mode), http_send!: Support.no_http! }, cassette_name) {
			Err(CassetteReadFailed(message)) => Assert.contains(message, "tests/tmp/error_cassette_read_failed.json")?
			Err(other) => return Err(ExpectedCassetteReadFailed(Str.inspect(other)))
			Ok(_) => return Err(ExpectedCassetteReadFailed("a client"))
		}
	}
	Support.reset!(cassette_name)
}
