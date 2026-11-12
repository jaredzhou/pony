///|
test "method shortcuts register routes for the expected HTTP methods" {
  let r = Router::Router()
  let handler : Handler = ctx => ctx.no_content()

  r.get("/get", handler, name="get")
  r.post("/post", handler, name="post")
  r.put("/put", handler, name="put")
  r.delete("/delete", handler, name="delete")
  r.patch("/patch", handler, name="patch")
  r.head("/head", handler, name="head")
  r.options("/options", handler, name="options")
  let middleware : Middleware = next => next
  r.get("/middleware", mws=[middleware], handler, name="middleware")

  assert_true(
    r.route(Get, "/get") is RouteResult::Found(ep, _) &&
    ep.pattern == "/get" &&
    ep.name == "get",
  )
  assert_true(
    r.route(Post, "/post") is RouteResult::Found(ep, _) &&
    ep.pattern == "/post" &&
    ep.name == "post",
  )
  assert_true(
    r.route(Put, "/put") is RouteResult::Found(ep, _) &&
    ep.pattern == "/put" &&
    ep.name == "put",
  )
  assert_true(
    r.route(Delete, "/delete") is RouteResult::Found(ep, _) &&
    ep.pattern == "/delete" &&
    ep.name == "delete",
  )
  assert_true(
    r.route(Patch, "/patch") is RouteResult::Found(ep, _) &&
    ep.pattern == "/patch" &&
    ep.name == "patch",
  )
  assert_true(
    r.route(Head, "/head") is RouteResult::Found(ep, _) &&
    ep.pattern == "/head" &&
    ep.name == "head",
  )
  assert_true(
    r.route(Options, "/options") is RouteResult::Found(ep, _) &&
    ep.pattern == "/options" &&
    ep.name == "options",
  )
  assert_true(
    r.route(Get, "/middleware") is RouteResult::Found(ep, _) &&
    ep.pattern == "/middleware" &&
    ep.name == "middleware",
  )
}

///|
test "invalid add leaves the router unchanged" {
  let r = Router::Router()
  let handler : Handler = ctx => ctx.no_content()
  let before = r.to_string()

  for pattern in ["missing-slash", "/partial/{id", "/partial/*rest"] {
    try r.add(Get, pattern, handler) catch {
      _ => ()
    } noraise {
      _ => fail("expected invalid route: \{pattern}")
    }
  }

  assert_eq(r.to_string(), before)
  r.get("/partial/ok", handler)
  assert_true(r.route(Get, "/partial/ok") is RouteResult::Found(_, _))
}
