## Looks up a repository with the GitHub API through a VCR client.
##
## `repo_summary!` stands for your own code. It takes its HTTP function as an
## argument, so an app passes basic-cli's `Http.send!` and a test passes a
## client, which has the same type.
##
## The cassette examples/cassettes/example_cassette.json is committed, so this
## replays the recorded response and never touches the network. Run it with
## `VCR_MODE=replace` to send the request for real and record it again.
##
## Run from the repository root: `roc examples/example.roc`
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.28.0/AP9SGT1yrhCKcFxKcoA5tBkNCM6ibBjBxcQGMTb6krev.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/2.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	vcr: "../package/main.roc",
}

import pf.Env
import pf.Http
import pf.OsStr
import pf.Path
import pf.Stdout
import http.Request
import vcr.Vcr

## A line about the repository `name`, fetched with `send!`
repo_summary! = |send!, name| {
	request = Request.from_method(GET)
		.with_uri("https://api.github.com/repos/${name}")
		.add_header("User-Agent", "roc-vcr-example")
	response = send!(request)?
	repo : { full_name : Str, description : Str, stargazers_count : U64 }
	repo = Json.parse(Str.from_utf8_lossy(response.body()))?
	Ok("${repo.full_name}: ${repo.description} (${repo.stargazers_count.to_str()} stars)")
}

main! : List(OsStr) => Try({}, _)
main! = |_args| {
	mode = Vcr.parse_mode(Env.var_str!(OsStr.from_str("VCR_MODE")) ?? "replay")?

	# One client per cassette. Wherever your code takes `Http.send!`, a test
	# hands it the client instead.
	client! = Vcr.init!({ cassette_dir: Path.utf8("examples/cassettes"), http_send!: Http.send!, mode }, "example_cassette")?

	Stdout.line!(repo_summary!(client!, "roc-lang/roc")?)
}
