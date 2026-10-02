app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.26.0/EuuihZ91yAY1ANck1QytRBcW2jexEfH6yVmxcPCHEHDz.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/2.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	spec: "https://github.com/niclas-ahden/roc-spec/releases/download/0.6.0/9ThTkhd7zrviwQpM3LvGd7pvzGhr4ZXNmWJV7pTJc9AJ.tar.zst",
	vcr: "../package/main.roc",
}

import pf.OsStr
import spec.Assert
import vcr.Vcr
import FailingDir
import Support

cassette_name : Str
cassette_name = "error_cassette_delete_failed"

## `init!` does the deleting, and reports a failure to delete instead of
## making a client.
main! : List(OsStr) => Try({}, _)
main! = |_args| {
	Support.reset!(cassette_name)?
	request = Support.request(GET, "https://api.test.com/")

	record! = Vcr.init!(Support.config(Once), cassette_name)?
	_ = record!(request)?

	cassette_dir = FailingDir.{ path: Support.cassette_dir, failing: Delete }
	match Vcr.init!({ cassette_dir, http_send!: Support.no_http!, mode: Replace }, cassette_name) {
		Err(CassetteDeleteFailed(message)) => {
			Assert.contains(message, "tests/tmp/error_cassette_delete_failed.json")?
			Assert.contains(message, "PermissionDenied")
		}
		Err(other) => Err(ExpectedCassetteDeleteFailed(Str.inspect(other)))
		Ok(_) => Err(ExpectedCassetteDeleteFailed("a client"))
	}
}
