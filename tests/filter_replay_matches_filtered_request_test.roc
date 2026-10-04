app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.28.0/AP9SGT1yrhCKcFxKcoA5tBkNCM6ibBjBxcQGMTb6krev.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/2.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	spec: "https://github.com/niclas-ahden/roc-spec/releases/download/0.6.0/9ThTkhd7zrviwQpM3LvGd7pvzGhr4ZXNmWJV7pTJc9AJ.tar.zst",
	vcr: "../package/main.roc",
}

import pf.OsStr
import spec.Assert
import vcr.Vcr
import Support

cassette_name : Str
cassette_name = "filter_replay_matches_filtered_request"

## The cassette holds the placeholder, so a replayed request is filtered the
## same way before it is matched.
main! : List(OsStr) => Try({}, _)
main! = |_args| {
	Support.reset!(cassette_name)?
	filters = [{ find: "4711", replace: "<ACCOUNT>" }]
	request = Support.request(POST, "https://api.test.com/data?account=4711").with_body(Str.to_utf8("account=4711"))

	record! = Vcr.init!({ ..Support.config(Once), replace_sensitive_data: filters }, cassette_name)?
	_ = record!(request)?

	replay! = Vcr.init!({ ..Support.replay_config, replace_sensitive_data: filters }, cassette_name)?
	replayed = replay!(request)?

	# What is replayed is the filtered recording
	Assert.contains(Str.from_utf8_lossy(replayed.body()), "account=<ACCOUNT>")
}
