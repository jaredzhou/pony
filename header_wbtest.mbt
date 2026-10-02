///|
test "canonicalHeaderKey title-cases each dash-separated token" {
  inspect(canonicalHeaderKey("content-type"), content="Content-Type")
  inspect(canonicalHeaderKey("X-USER-ID"), content="X-User-Id")
  inspect(canonicalHeaderKey("accept-encoding"), content="Accept-Encoding")
}

///|
test "canonicalHeaderKey handles empty and single-token input" {
  inspect(canonicalHeaderKey(""), content="")
  inspect(canonicalHeaderKey("a"), content="A")
  inspect(canonicalHeaderKey("x--y"), content="X--Y")
}
