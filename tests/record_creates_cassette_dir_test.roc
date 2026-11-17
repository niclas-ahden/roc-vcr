app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.31.0/Ff3fkK1TjYTVxMj9V21FP24ojTJXYk314Fbo1whBZ6Yf.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/2.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	spec: "https://github.com/niclas-ahden/roc-spec/releases/download/0.7.1/GXr8UJ7VDaJ8HYykmVYtTjLs7X4bZeE9YDTzAHoVXFJ9.tar.zst",
	vcr: "../package/main.roc",
}

import pf.OsStr
import spec.Assert
import vcr.Vcr
import Support

cassette_name : Str
cassette_name = "record_creates_cassette_dir"

## Recording creates `cassette_dir` when it does not exist yet.
main! : List(OsStr) => Try({}, _)
main! = |_args| {
	Support.reset!(cassette_name)?
	nested = Support.cassette_dir.join("created").join("by_vcr")
	_ = Support.cassette_dir.join("created").delete_all!()

	client! = Vcr.init!({ ..Support.config(Once), cassette_dir: nested }, cassette_name)?
	_ = client!(Support.request(GET, "https://api.test.com/"))?

	Assert.true(nested.join("${cassette_name}.json").exists!()?)
}
