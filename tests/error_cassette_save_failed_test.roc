app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.32.0/3MnQnCrtfe6XS5qx58MnAGU6iWk8i1N24MYfoejcWeax.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/2.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	spec: "https://github.com/niclas-ahden/roc-spec/releases/download/0.7.1/GXr8UJ7VDaJ8HYykmVYtTjLs7X4bZeE9YDTzAHoVXFJ9.tar.zst",
	vcr: "../package/main.roc",
}

import pf.OsStr
import spec.Assert
import vcr.Vcr
import FailingDir
import Support

cassette_name : Str
cassette_name = "error_cassette_save_failed"

main! : List(OsStr) => Try({}, _)
main! = |_args| {
	Support.reset!(cassette_name)?
	cassette_dir = FailingDir.{ path: Support.cassette_dir, failing: Write }
	client! = Vcr.init!({ cassette_dir, http_send!: Support.http_send!, mode: Once }, cassette_name)?

	match client!(Support.request(GET, "https://api.test.com/")) {
		Err(CassetteSaveFailed(message)) => {
			Assert.contains(message, "tests/tmp/error_cassette_save_failed.json")?
			Assert.contains(message, "DiskFull")
		}
		other => Err(ExpectedCassetteSaveFailed(Str.inspect(other)))
	}
}
