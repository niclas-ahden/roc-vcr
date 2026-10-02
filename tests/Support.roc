## What every test in this directory shares: a mock `http_send!`, configs
## built on basic-cli's `Path`, and helpers for the cassettes a test records.
##
## No test touches the network. Recording tests use the mock, which answers
## with an echo of the request, and write their cassettes to `tests/tmp`.
import pf.Path
import http.Method
import http.Request
import http.Response
import vcr.Vcr

Support :: [].{

	## Where recording tests write their cassettes. Ignored by git.
	cassette_dir : Path
	cassette_dir = Path.utf8("tests/tmp")

	## The committed cassettes, which some tests replay.
	fixture_dir : Path
	fixture_dir = Path.utf8("tests/cassettes")

	## Answers 200 with the method, URI and body of the request echoed in the
	## body, so a test can tell which request a response belongs to.
	http_send! : Request => Try(Response, [MockHttpError])
	http_send! = |req|
		Ok(
			Response.from_status(200)
				.add_header("X-Mock", "true")
				.with_body(Str.to_utf8("response-for:${req.method_str()}:${req.uri()}:body=${Str.from_utf8_lossy(req.body())}")),
		)

	## Fails on every request. For clients that must answer from the cassette.
	no_http! : Request => Try(Response, [UnexpectedHttpRequest(Str)])
	no_http! = |req| Err(UnexpectedHttpRequest(req.uri()))

	## A `Replay` config reading from [cassette_dir], with [no_http!] as its
	## `http_send!` so a request that reaches the network fails the test.
	replay_config : Vcr.Config(Path, _)
	replay_config = { cassette_dir, http_send!: no_http!, mode: Replay }

	## A config for `mode` that records from the mock into [cassette_dir].
	config : Vcr.Mode -> Vcr.Config(Path, _)
	config = |mode| { cassette_dir, http_send!, mode }

	## A request with no headers and no body.
	request : Method, Str -> Request
	request = |method, uri| Request.from_method(method).with_uri(uri)

	## What a test compares a response by. roc-lang/http's `Response` has no
	## `==` of its own.
	fields : Response -> { status : U16, headers : List((Str, Str)), body : List(U8) }
	fields = |response| {
		status: response.status(),
		headers: response.headers().map(|header| (header.name, header.value)),
		body: response.body(),
	}

	## Make sure [cassette_dir] exists and holds no cassette called `name`,
	## which a failed or earlier run may have left behind. A test that
	## records into a cassette that is already there would replay it instead,
	## and pass without recording anything, so a cassette that cannot be
	## removed fails the test.
	reset! : Str => Try({}, _)
	reset! = |name| {
		cassette_dir.create_all!()?
		file = cassette_dir.join("${name}.json")
		# A file, or the directory error_cassette_read_failed_test puts there
		_ = file.delete!()
		_ = file.delete_all!()
		if file.exists!()? {
			Err(CassetteLeftBehind(file.display()))
		} else {
			Ok({})
		}
	}

	## The JSON text of a recorded cassette.
	read_cassette! : Str => Try(Str, _)
	read_cassette! = |name| cassette_dir.join("${name}.json").read_utf8!()

	## Decode a recorded cassette the way a user of the package would.
	load_cassette! : Str => Try(Vcr.Cassette, _)
	load_cassette! = |name| Vcr.decode_cassette(cassette_dir.join("${name}.json").read_bytes!()?)
}
