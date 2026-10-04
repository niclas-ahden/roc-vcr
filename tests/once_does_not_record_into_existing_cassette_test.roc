app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.28.0/AP9SGT1yrhCKcFxKcoA5tBkNCM6ibBjBxcQGMTb6krev.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/2.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	spec: "https://github.com/niclas-ahden/roc-spec/releases/download/0.6.0/9ThTkhd7zrviwQpM3LvGd7pvzGhr4ZXNmWJV7pTJc9AJ.tar.zst",
	vcr: "../package/main.roc",
}

import pf.OsStr
import vcr.Vcr
import Support

cassette_name : Str
cassette_name = "once_does_not_record_into_existing_cassette"

## A request the existing cassette does not hold is an error in `Once` mode,
## it is not sent and recorded.
main! : List(OsStr) => Try({}, _)
main! = |_args| {
	Support.reset!(cassette_name)?

	first! = Vcr.init!(Support.config(Once), cassette_name)?
	_ = first!(Support.request(GET, "https://api.test.com/recorded"))?

	second! = Vcr.init!(Support.config(Once), cassette_name)?
	match second!(Support.request(GET, "https://api.test.com/new")) {
		Err(InteractionNotFound(_)) => Ok({})
		other => Err(ExpectedInteractionNotFound(Str.inspect(other)))
	}
}
