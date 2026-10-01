package
	[Vcr]
	{
		# The request and response types a platform's `send!` takes and
		# returns, so `http_send!` can be basic-cli's `Http.send!` as it is.
		http: "https://github.com/roc-lang/http/releases/download/2.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
		# For bodies that are not UTF-8, which a cassette stores as base64.
		base64: "https://github.com/niclas-ahden/roc-base64/releases/download/1.0.1/DQBxATK6BtaCWe56bCmkMgdKJR2Ym8NiZZLhYCAgtLac.tar.zst",
	}
