app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.26.0/EuuihZ91yAY1ANck1QytRBcW2jexEfH6yVmxcPCHEHDz.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/2.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	spec: "https://github.com/niclas-ahden/roc-spec/releases/download/0.6.0/9ThTkhd7zrviwQpM3LvGd7pvzGhr4ZXNmWJV7pTJc9AJ.tar.zst",
	vcr: "../package/main.roc",
}

import pf.OsStr exposing [OsStr]
import http.Request exposing [Request]
import http.Response exposing [Response]
import spec.Assert
import vcr.Vcr
import Support

## An API that pages through three items, one per page, the way YouTube's
## does: a page names the next one by a token in the field `next_field`, and
## the request for that page sends it back in the query parameter `param`.
paged_api : Str, Str -> (Request => Try(Response, [MockHttpError]))
paged_api = |param, next_field| |request| {
	token =
		match request.uri().split_first("${param}=") {
			Ok({ before: _, after }) => after
			Err(_) => ""
		}
	(item, next) =
		match token {
			"" => ("a", ",\"${next_field}\":\"CAUQAA\"")
			"CAUQAA" => ("b", ",\"${next_field}\":\"CAoQAA\"")
			_ => ("c", "")
		}
	Ok(Response.from_status(200).with_body(Str.to_utf8("{\"item\":\"${item}\"${next}}")))
}

## The string value of the field `name` in `json`
field : Str, Str -> Try(Str, [Missing])
field = |json, name| {
	after_name = json.split_first("\"${name}\":\"") ? |_| Missing
	value = after_name.after.split_first("\"") ? |_| Missing
	Ok(value.before)
}

## Every item, page by page, the way the code under test would fetch them.
## A client that answers the same page over and over makes it give up.
all_items! = |client!, param, next_field| {
	var $items = []
	var $query = ""
	var $more = Bool.True
	while $more and $items.len() < 10 {
		response = client!(Support.request(GET, "https://api.test.com/videos?part=id${$query}"))?
		body = Str.from_utf8_lossy(response.body())
		$items = $items.append(field(body, "item") ? |_| NoItem(body))
		match field(body, next_field) {
			Ok(token) => {
				$query = "&${param}=${token}"
			}
			Err(Missing) => {
				$more = Bool.False
			}
		}
	}
	if $more Err(StuckOnAPage($items)) else Ok($items)
}

## Record three pages, then replay them. Every request after the first sends
## the token of its page, so the token has to stay in the cassette for the
## requests to differ.
pages_replay! = |cassette_name, param, next_field, keep| {
	Support.reset!(cassette_name)?

	record! = Vcr.init!({ ..Support.config(Once), http_send!: paged_api(param, next_field), keep }, cassette_name)?
	Assert.eq(all_items!(record!, param, next_field)?, ["a", "b", "c"])?

	json = Support.read_cassette!(cassette_name)?
	Assert.contains(json, "${param}=CAoQAA")?

	replay! = Vcr.init!({ ..Support.replay_config, keep }, cassette_name)?
	Assert.eq(all_items!(replay!, param, next_field)?, ["a", "b", "c"])
}

## A token that pages through results ends in `token` like a secret, but it
## stays in the cassette, by the built-in paging names or by `keep`.
main! : List(OsStr) => Try({}, _)
main! = |_args| {
	pages_replay!("replay_pages_by_token", "pageToken", "nextPageToken", [])?
	pages_replay!("replay_pages_by_kept_token", "resume_token", "resume_token", ["resume_token"])
}
