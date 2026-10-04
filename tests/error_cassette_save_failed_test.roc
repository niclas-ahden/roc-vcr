app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.28.0/AP9SGT1yrhCKcFxKcoA5tBkNCM6ibBjBxcQGMTb6krev.tar.zst",
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
