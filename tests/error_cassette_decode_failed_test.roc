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
cassette_name = "error_cassette_decode_failed"

## A cassette that does not parse is an error from `init!` in every mode
## that reads it, and `Once` does not record over it.
main! : List(OsStr) => Try({}, _)
main! = |_args| {
	Support.reset!(cassette_name)?
	malformed = "{ this is not valid json }"
	Support.cassette_dir.join("${cassette_name}.json").write_utf8!(malformed)?

	match Vcr.init!(Support.replay_config, cassette_name) {
		Err(CassetteDecodeFailed(message)) => Assert.contains(message, "tests/tmp/error_cassette_decode_failed.json")?
		Err(other) => return Err(ExpectedCassetteDecodeFailed(Str.inspect(other)))
		Ok(_) => return Err(ExpectedCassetteDecodeFailed("a client"))
	}

	match Vcr.init!(Support.config(Once), cassette_name) {
		Err(CassetteDecodeFailed(_)) => {}
		Err(other) => return Err(ExpectedCassetteDecodeFailed(Str.inspect(other)))
		Ok(_) => return Err(ExpectedCassetteDecodeFailed("a client"))
	}
	Assert.eq(Support.read_cassette!(cassette_name)?, malformed)
}
