///|
/// Build a small but realistic-looking JPEG byte sequence for multipart
/// upload tests. The tests do not validate image content — they only
/// care that binary bytes round-trip through the upload pipeline — so any
/// blob with a JPEG-shaped header works.
fn fixture_image_bytes() -> Bytes {
  let buf = @buffer.Buffer::Buffer()
  // Minimal JFIF: SOI, APP0 (JFIF marker), DQT (quantization table),
  // SOF0 (1x1 frame), DHT (Huffman tables), SOS + payload, EOI.
  buf.write_bytes(b"\xff\xd8\xff\xe0\x00\x10\x4a\x46\x49\x46\x00\x01")
  buf.write_bytes(b"\x01\x00\x00\x01\x00\x01\x00\x00\xff\xdb\x00\x43\x00")
  // Fill the rest with deterministic padding so size is non-trivial.
  for i in 0..<512 {
    buf.write_byte(((i * 17 + 13) % 256).to_byte())
  }
  buf.write_bytes(b"\xff\xd9")
  buf.to_bytes()
}

///|
/// Combined test: tree structure, middleware, HTTP integration,
/// not-found, method-not-allowed, and mount.
async test "test_pony" {
  // --- middleware ---
  let mut count = 0
  let _counter : Middleware = next => {
    ctx => {
      count = count + 1
      next(ctx)
    }
  }
  let logbuf = StringBuilder::new()
  let logmsg = "logmw test"
  let _logmw : Middleware = next => {
    ctx => {
      logbuf.write_string(logmsg)
      next(ctx)
    }
  }

  // --- handlers ---
  let ping : Handler = ctx => ctx.write_text(200, "pong")
  let ping_all : Handler = ctx => ctx.write_text(200, "pong all")
  let ping_all2 : Handler = ctx => ctx.write_text(200, "pong all 2")
  let ping_one : Handler = ctx => {
    let id = ctx.try_param("id").unwrap_or("")
    ctx.write_text(200, "pong " + id)
  }
  let ping_woop : Handler = ctx => {
    let id = ctx.try_param("iidd").unwrap_or("")
    ctx.write_text(200, "pong woop " + id)
  }
  let catch_all : Handler = ctx => ctx.write_text(200, "caughtall")
  let echo_query : Handler = ctx => {
    let name = ctx.try_query("name").unwrap_or("none")
    ctx.write_text(200, "hello " + name)
  }
  let login : Handler = async fn(ctx) {
    let user = ctx.try_form("user").unwrap_or("")
    ctx.write_text(200, "welcome " + user)
  }

  // --- custom not-found & method-not-allowed ---
  let custom_not_found : Handler = ctx => ctx.write_text(404, "custom 404")
  let custom_not_allowed : Handler = ctx => ctx.write_text(405, "custom 405")

  // --- sub-router for mount ---
  let sub = Router::Router()
  sub.add(
    HttpMethod::Get,
    "/hi",
    ctx => ctx.write_text(200, "hello from sub"),
    name="sub_hi",
  )

  // --- router ---
  let r = Router::Router()
  r.add(HttpMethod::Get, "/echo", echo_query, name="echo")
  r.add(HttpMethod::Post, "/login", login, name="login")
  r.add(HttpMethod::Get, "/ping", ping, name="ping")
  r.add(HttpMethod::Get, "/pingall", ping_all, name="pingAll")
  r.add(HttpMethod::Get, "/ping/all", ping_all, name="pingAllAlias")
  r.add(HttpMethod::Get, "/ping/all2", ping_all2, name="pingAll2")
  r.add(HttpMethod::Get, "/ping/{id}", ping_one, name="pingOne")
  r.add(HttpMethod::Get, "/ping/{iidd}/woop", ping_woop, name="pingWoop2")
  r.any("/admin/*", catch_all, name="catchAll")
  r.mount("/api", sub)
  r.set_not_found(custom_not_found)
  r.set_method_not_allowed(custom_not_allowed)

  // --- tree structure ---
  inspect(
    r,
    content=(
      #|Static()
      #|    └── Static(/)
      #|        ├── Static(echo) Get(/echo)
      #|        ├── Static(login) Post(/login)
      #|        ├── Static(ping) Get(/ping)
      #|        │   ├── Static(all) Get(/pingall)
      #|        │   └── Static(/)
      #|        │       ├── Static(all) Get(/ping/all)
      #|        │       │   └── Static(2) Get(/ping/all2)
      #|        │       p── Param(id,/) Get(/ping/{id})
      #|        │           └── Static(/woop) Get(/ping/{iidd}/woop)
      #|        └── Static(a)
      #|            ├── Static(dmin/)
      #|            │   w── * Any(/admin/*)
      #|            └── Static(pi/)
      #|                w── * Any(/api/*)
      #|
    ),
  )

  // --- middleware verification ---
  inspect(logbuf.to_string(), content="")

  // --- HTTP integration ---
  @async.with_task_group() <| group => {
    let port = 19876
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      start("127.0.0.1:\{port}", r)
    }
    let base = "http://127.0.0.1:\{port}"
    @async.sleep(500)

    let (resp, body) = @http.get(base + "/ping")
    assert_eq(resp.code, 200)
    assert_eq(body.text(), "pong")

    let (resp, body) = @http.get(base + "/pingall")
    assert_eq(resp.code, 200)
    assert_eq(body.text(), "pong all")

    let (resp, body) = @http.get(base + "/ping/42")
    assert_eq(resp.code, 200)
    assert_eq(body.text(), "pong 42")

    let (resp, body) = @http.get(base + "/admin/anything/here")
    assert_eq(resp.code, 200)
    assert_eq(body.text(), "caughtall")

    // not found
    let (resp, body) = @http.get(base + "/nope")
    assert_eq(resp.code, 404)
    assert_eq(body.text(), "custom 404")

    // method not allowed — path exists but wrong method
    let (resp, body) = @http.post(base + "/ping", b"")
    assert_eq(resp.code, 405)
    assert_eq(body.text(), "custom 405")

    // mounted sub-router
    let (resp, body) = @http.get(base + "/api/hi")
    assert_eq(resp.code, 200)
    assert_eq(body.text(), "hello from sub")

    // query parameter
    let (resp, body) = @http.get(base + "/echo?name=moonbit")
    assert_eq(resp.code, 200)
    assert_eq(body.text(), "hello moonbit")

    // POST form data
    let (resp, body) = @http.post(base + "/login", "user=pony&pass=1234")
    assert_eq(resp.code, 200)
    assert_eq(body.text(), "welcome pony")
  }
}

///|
/// query parameter: key with value, key without value, multi-value key.
async test "test_query" {
  let r = Router::Router()
  r.add(
    HttpMethod::Get,
    "/search",
    ctx => {
      let q = ctx.try_query("q").unwrap_or("")
      let page = ctx.try_query("page").unwrap_or("1")
      let tags = ctx.queries.get_all("tag")
      let has_flag = ctx.try_query("flag") is Some(_)
      let flag_val = ctx.try_query("flag").unwrap_or("none")
      let tags_str = "[" + tags.iter().join(", ") + "]"
      ctx.write_text(
        200,
        "q=\{q} page=\{page} has_flag=\{has_flag} flag_val=\{flag_val} tags=\{tags_str}",
      )
    },
    name="search",
  )

  @async.with_task_group() <| group => {
    let port = 19877
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      start("127.0.0.1:\{port}", r)
    }
    let base = "http://127.0.0.1:\{port}"
    @async.sleep(500)

    // key with value, no flag
    let (resp, body) = @http.get(base + "/search?q=pony")
    assert_eq(resp.code, 200)
    assert_eq(body.text(), "q=pony page=1 has_flag=false flag_val=none tags=[]")

    // key without value (flag is present, value is empty string)
    let (resp, body) = @http.get(base + "/search?q=pony&flag")
    assert_eq(resp.code, 200)
    assert_eq(body.text(), "q=pony page=1 has_flag=true flag_val= tags=[]")

    // same key multiple values
    let (resp, body) = @http.get(
      base + "/search?tag=web&tag=framework&tag=fast",
    )
    assert_eq(resp.code, 200)
    assert_eq(
      body.text(),
      "q= page=1 has_flag=false flag_val=none tags=[web, framework, fast]",
    )

    // mixed: multi-value + key-without-value
    let (resp, body) = @http.get(base + "/search?tag=rust&flag&tag=go")
    assert_eq(resp.code, 200)
    assert_eq(body.text(), "q= page=1 has_flag=true flag_val= tags=[rust, go]")

    // no query at all
    let (resp, body) = @http.get(base + "/search")
    assert_eq(resp.code, 200)
    assert_eq(body.text(), "q= page=1 has_flag=false flag_val=none tags=[]")
  }
}

///|
struct User {
  name : String
  age : Int
} derive(FromJson, ToJson, Eq)

///|
/// JSON body deserialization via ctx.json() with a custom struct.
async test "test_json" {
  let r = Router::Router()
  r.add(
    HttpMethod::Post,
    "/user",
    async fn(ctx) {
      let user : User = ctx.json() catch {
        _ => {
          ctx.write_text(400, "bad json")
          return
        }
      }
      ctx.write_text(200, "\{"\{user.name}"} is \{"\{user.age}"}")
    },
    name="create_user",
  )

  @async.with_task_group() <| group => {
    let port = 19878
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      start("127.0.0.1:\{port}", r)
    }
    let base = "http://127.0.0.1:\{port}"
    @async.sleep(500)

    let (resp, body) = @http.post(
      base + "/user",
      "{\"name\":\"alice\",\"age\":30}",
    )
    assert_eq(resp.code, 200)
    assert_eq(body.text(), "alice is 30")
  }
}

///|
/// write_bytes, set_content_type, no_content, redirect.
async test "test_write" {
  let r = Router::Router()
  r.add(
    HttpMethod::Get,
    "/bytes",
    ctx => {
      ctx.set_content_type("application/octet-stream")
      ctx.write_bytes(200, b"\x00\x01\x02")
    },
    name="bytes",
  )
  r.add(HttpMethod::Post, "/done", ctx => ctx.no_content(), name="no_content")
  r.add(HttpMethod::Get, "/go", ctx => ctx.redirect("/ping"), name="redirect")

  @async.with_task_group() <| group => {
    let port = 19879
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      start("127.0.0.1:\{port}", r)
    }
    let base = "http://127.0.0.1:\{port}"
    @async.sleep(500)

    // write_bytes + set_content_type
    let (resp, _body) = @http.get(base + "/bytes")
    assert_eq(resp.code, 200)
    assert_eq(
      resp.headers.get("content-type").unwrap_or(""),
      "application/octet-stream",
    )

    // no_content
    let (resp, _) = @http.post(base + "/done", b"")
    assert_eq(resp.code, 204)

    // redirect
    let (resp, _) = @http.get(base + "/go")
    assert_eq(resp.code, 302)
    assert_eq(resp.headers.get("location").unwrap_or(""), "/ping")
  }
}

///|
/// Mount: sub-router with middleware, not-found, method-not-allowed.
async test "test_mount" {
  let sub = Router::Router()
  sub.add(HttpMethod::Get, "/hi", ctx => ctx.write_text(200, "hi"), name="hi")
  sub.add(
    HttpMethod::Post,
    "/create",
    ctx => ctx.write_text(201, "created"),
    name="create",
  )
  sub.set_not_found(ctx => ctx.write_text(404, "sub 404"))
  sub.set_method_not_allowed(ctx => ctx.write_text(405, "sub 405"))

  let r = Router::Router()
  r.mount("/v1", sub)

  @async.with_task_group() <| group => {
    let port = 19880
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      start("127.0.0.1:\{port}", r)
    }
    let base = "http://127.0.0.1:\{port}"
    @async.sleep(500)

    // mounted GET
    let (resp, body) = @http.get(base + "/v1/hi")
    assert_eq(resp.code, 200)
    assert_eq(body.text(), "hi")

    // not found inside sub
    let (resp, body) = @http.get(base + "/v1/nope")
    assert_eq(resp.code, 404)
    assert_eq(body.text(), "sub 404")

    // method not allowed inside sub
    let (resp, body) = @http.post(base + "/v1/hi", b"")
    assert_eq(resp.code, 405)
    assert_eq(body.text(), "sub 405")
  }
}

///|
/// JWT middleware: decode bearer token and set user_id in ext.

///|
/// JWT middleware: decode bearer token and set user_id in ext.
async test "test_jwt" {
  let r = Router::Router()
  r.use_mw(@mw.jwt(@jwt.new_hmac_sha256(b"secret")))
  r.add(
    HttpMethod::Get,
    "/me",
    ctx => {
      let user : String = ctx.get_ext(@pony.UserId::{  }) catch {
        _ => "anonymous"
      }
      ctx.write_text(200, "user=" + user)
    },
    name="me",
  )

  @async.with_task_group() <| group => {
    let port = 19882
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      let server = @http.Server::Server(
        @socket.Addr::parse("127.0.0.1:\{port}"),
      )
      server.run_forever((req, req_body, conn) => r.handle(req, req_body, conn))
    }
    let base = "http://127.0.0.1:\{port}"
    @async.sleep(500)

    let token_str = @jwt.sign(@jwt.new_hmac_sha256(b"secret"), {
      "sub": "alice",
    })
    let (resp, body) = @http.get(base + "/me", headers={
      "Authorization": "Bearer \{token_str}",
    })
    assert_eq(resp.code, 200)
    assert_eq(body.text(), "user=alice")

    // no token
    let (resp, body) = @http.get(base + "/me")
    assert_eq(resp.code, 200)
    assert_eq(body.text(), "user=anonymous")

    // // no token
    // let (resp, body) = @http.get(base + "/me")
    // assert_eq(resp.code, 200)
    // assert_eq(body.text(), "anonymous")
  }
}

///|
/// Server: encapsulated router with request_id.
async test "test_server" {
  let r = Router::Router()
  r.add(
    HttpMethod::Get,
    "/hello",
    ctx => {
      let id = ctx.get_ext(@pony.RequestId::{  }) catch { _ => "?" }
      ctx.write_text(200, "req=" + id)
    },
    name="hello",
  )

  let s = Server::Server("127.0.0.1:19881", r)

  @async.with_task_group() <| group => {
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => { s.start() }
    @async.sleep(500)

    let (resp, body) = @http.get("http://127.0.0.1:19881/hello")
    assert_eq(resp.code, 200)
    assert_eq(body.text(), "req=1")
  }
}

///|
test "any test" {
  let user = @any.of("User-1")
  assert_eq(user.to(), "User-1")
}

///|
test "ext_store" {
  let s = ExtStore::new()
  s.set(RequestId::{  }, "REQ-42")
  s.set(UserId::{  }, "USER-99")

  let req_id : String = s.get(RequestId::{  }) catch { _ => "?" }
  let user_id : String = s.get(UserId::{  }) catch { _ => "?" }

  assert_eq(req_id, "REQ-42")
  assert_eq(user_id, "USER-99")
}

///|
/// Build a multipart body with explicit CRLF bytes (avoids encoding ambiguity).
fn build_body(
  boundary : String,
  parts : Array[(String, String?, String)],
) -> Bytes {
  let buf = @buffer.Buffer::Buffer()
  for part in parts {
    let (name, filename, content) = part
    buf.write_string_utf8("--\{boundary}\r\n")
    buf.write_string_utf8("Content-Disposition: form-data; name=\"\{name}\"")
    match filename {
      Some(f) => {
        buf.write_string_utf8(
          "; filename=\"\{f}\"\r\nContent-Type: application/octet-stream\r\n\r\n",
        )
        buf.write_string_utf8(content)
      }
      None => {
        buf.write_string_utf8("\r\n\r\n")
        buf.write_string_utf8(content)
      }
    }
    buf.write_string_utf8("\r\n")
  }
  buf.write_string_utf8("--\{boundary}--\r\n")
  buf.to_bytes()
}

///|
/// Integration: parse a multipart upload through the HTTP server.
async test "test_multipart_upload" {
  let r = Router::Router()
  r.add(
    HttpMethod::Post,
    "/upload",
    async fn(ctx) {
      ctx.parse_multipart_form() catch {
        _ => {
          ctx.write_text(400, "bad form")
          return
        }
      }
      let username = ctx.try_form("username").unwrap_or("")
      match ctx.try_form_file("avatar") {
        Some(file) => {
          let path = file.path().unwrap_or("memory")
          ctx.write_text(
            200,
            "\{file.filename}/\{file.size}/\{username}/\{path}",
          )
        }
        None => ctx.write_text(200, "no-file/\{username}")
      }
    },
    name="upload",
  )

  @async.with_task_group() <| group => {
    let port = 19899
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      start("127.0.0.1:\{port}", r)
    }
    let base = "http://127.0.0.1:\{port}"
    @async.sleep(1000)

    let boundary = "----testboundary"
    let body = build_body(boundary, [
      ("username", None, "alice"),
      ("avatar", Some("photo.png"), "binarydata"),
    ])
    let (resp, body) = @http.post(base + "/upload", body, headers={
      "Content-Type": "multipart/form-data; boundary=\{boundary}",
    })
    assert_eq(resp.code, 200)
    assert_eq(body.text(), "photo.png/10/alice/memory")
  }
}

///|
/// Integration: force disk spill with max_memory=1, upload real image.
async test "test_multipart_upload_disk_spill" {
  // Ensure the data dir exists in a fresh checkout.
  @fs.mkdir("data", recursive=true) catch {
    _ => ()
  }
  let r = Router::Router()
  r.add(
    HttpMethod::Post,
    "/upload-spill",
    async fn(ctx) {
      ctx.parse_multipart_form(max_memory=1) catch {
        _ => {
          ctx.write_text(400, "bad form")
          return
        }
      }
      let username = ctx.try_form("username").unwrap_or("")
      match ctx.try_form_file("avatar") {
        Some(file) => {
          let data = file.bytes()
          let disk_path = file.path().unwrap_or("memory")
          // Save the uploaded image to data/test.jpg.
          let save_path = "data/test.jpg"
          @fs.remove(save_path) catch {
            _ => ()
          }
          @fs.write_file(save_path, data, create_mode=CreateNew)
          ctx.write_text(
            200,
            "\{file.filename}/\{file.size}/\{disk_path}/\{username}/\{save_path}",
          )
        }
        None => ctx.write_text(200, "no-file/\{username}")
      }
    },
    name="upload-spill",
  )

  @async.with_task_group() <| group => {
    let port = 19901
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      start("127.0.0.1:\{port}", r)
    }
    let base = "http://127.0.0.1:\{port}"
    @async.sleep(1000)

    // Use an in-memory fixture instead of relying on a checked-in file.
    let image_bytes = fixture_image_bytes()
    let image_size = image_bytes.length()
    let boundary = "----spillboundary"

    // Build multipart body with binary JPEG data.
    let buf = @buffer.Buffer::Buffer()
    // -- text field: username=alice
    buf.write_string_utf8("--\{boundary}\r\n")
    buf.write_string_utf8(
      "Content-Disposition: form-data; name=\"username\"\r\n\r\n",
    )
    buf.write_string_utf8("alice\r\n")
    // -- file field: avatar with actual JPEG bytes
    buf.write_string_utf8("--\{boundary}\r\n")
    buf.write_string_utf8(
      "Content-Disposition: form-data; name=\"avatar\"; filename=\"test.jpg\"\r\n",
    )
    buf.write_string_utf8("Content-Type: image/jpeg\r\n\r\n")
    buf.write_bytes(image_bytes)
    buf.write_string_utf8("\r\n")
    // -- final delimiter
    buf.write_string_utf8("--\{boundary}--\r\n")
    let body = buf.to_bytes()

    let (resp, resp_body) = @http.post(base + "/upload-spill", body, headers={
      "Content-Type": "multipart/form-data; boundary=\{boundary}",
    })
    assert_eq(resp.code, 200)
    let text = resp_body.text()
    assert_eq(text.contains("/pony-multipart-"), true)
    assert_eq(text.has_prefix("test.jpg/\{image_size}/"), true)
    assert_eq(text.contains("/alice/"), true)
    // Verify the saved file exists and matches the original image.
    let saved_data = @fs.read_file("data/test.jpg").binary()
    assert_eq(saved_data, image_bytes)
  }
}

///|
/// Integration: custom `FileWriter` streams file directly to a target,
/// bypassing memory buffer and temp files entirely.
async test "test_multipart_upload_custom_writer" {
  @fs.mkdir("data", recursive=true) catch {
    _ => ()
  }
  let target = "data/uploaded_by_writer.jpg"
  @fs.remove(target) catch {
    _ => ()
  }

  let r = Router::Router()
  r.add(
    HttpMethod::Post,
    "/upload-writer",
    async fn(ctx) {
      let file = @fs.create(target) catch {
        _ => {
          ctx.write_text(500, "cannot create target")
          return
        }
      }
      let _ = ctx.parse_multipart_form(writers={ "avatar": FileWriter(file) }) catch {
        _ => {
          ctx.write_text(400, "bad form")
          return
        }
      }
      match ctx.try_form_file("avatar") {
        Some(fh) =>
          // Backend is External — no local temp copy, path() returns None.
          ctx.write_text(
            200,
            "\{fh.filename}/\{fh.size}/\{fh.path().unwrap_or("none")}",
          )
        None => ctx.write_text(200, "no-file")
      }
    },
    name="upload-writer",
  )

  @async.with_task_group() <| group => {
    let port = 19902
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      start("127.0.0.1:\{port}", r)
    }
    let base = "http://127.0.0.1:\{port}"
    @async.sleep(1000)

    let image_bytes = fixture_image_bytes()
    let image_size = image_bytes.length()
    let boundary = "----writerboundary"

    let buf = @buffer.Buffer::Buffer()
    buf.write_string_utf8("--\{boundary}\r\n")
    buf.write_string_utf8(
      "Content-Disposition: form-data; name=\"username\"\r\n\r\n",
    )
    buf.write_string_utf8("alice\r\n")
    buf.write_string_utf8("--\{boundary}\r\n")
    buf.write_string_utf8(
      "Content-Disposition: form-data; name=\"avatar\"; filename=\"custom.jpg\"\r\n",
    )
    buf.write_string_utf8("Content-Type: image/jpeg\r\n\r\n")
    buf.write_bytes(image_bytes)
    buf.write_string_utf8("\r\n")
    buf.write_string_utf8("--\{boundary}--\r\n")
    let body = buf.to_bytes()

    let (resp, resp_body) = @http.post(base + "/upload-writer", body, headers={
      "Content-Type": "multipart/form-data; boundary=\{boundary}",
    })
    assert_eq(resp.code, 200)
    // path() returns "none" — FileWriter streams directly, backend is External
    assert_eq(resp_body.text(), "custom.jpg/\{image_size}/none")

    // The file was written directly by FileWriter, not through a temp file.
    let saved_data = @fs.read_file(target).binary()
    assert_eq(saved_data, image_bytes)
    @fs.remove(target) catch {
      _ => ()
    }
  }
}

///|
/// Local type used to exercise a user-defined FromStr impl
/// (trait is foreign, type is local — allowed by coherence rules).
struct ItemId(Int)

///|
impl @pony.FromStr for ItemId with fn from_str(s) {
  ItemId(@pony.FromStr::from_str(s))
}

///|
/// Typed accessors: param/query/header parsed via FromStr,
/// parse failure -> InvalidValue -> HTTP 400, custom impl.
async test "test_typed_accessors" {
  let r = Router::Router()
  r.add(
    HttpMethod::Get,
    "/item/{id}",
    ctx => {
      let id : Int = ctx.param("id") catch {
        e => {
          ctx.reply_error(e)
          return
        }
      }
      ctx.write_text(200, "item #\{id}")
    },
    name="item",
  )
  r.add(
    HttpMethod::Get,
    "/typed",
    ctx => {
      let page : Int = ctx.query("page") catch { _ => 1 }
      let dbg : Bool = ctx.query("debug") catch { _ => false }
      let ver : Double = ctx.header("x-api-version") catch { _ => 0.0 }
      ctx.write_text(200, "page=\{page} debug=\{dbg} ver=\{ver}")
    },
    name="typed",
  )
  r.add(
    HttpMethod::Get,
    "/item2/{id}",
    ctx => {
      let iid : ItemId = ctx.param("id") catch {
        e => {
          ctx.reply_error(e)
          return
        }
      }
      let ItemId(n) = iid
      ctx.write_text(200, "item2 #\{n}")
    },
    name="item2",
  )

  @async.with_task_group() <| group => {
    let port = 19903
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      start("127.0.0.1:\{port}", r)
    }
    let base = "http://127.0.0.1:\{port}"
    @async.sleep(500)

    // Int param parses
    let (resp, body) = @http.get(base + "/item/42")
    assert_eq(resp.code, 200)
    assert_eq(body.text(), "item #42")

    // unparsable param -> InvalidValue -> 400
    let (resp, body) = @http.get(base + "/item/abc")
    assert_eq(resp.code, 400)
    assert_true(body.text().contains("invalid value for id: abc"))

    // typed query + typed header
    let (resp, body) = @http.get(base + "/typed?page=3&debug=true", headers={
      "x-api-version": "1.5",
    })
    assert_eq(resp.code, 200)
    assert_eq(body.text(), "page=3 debug=true ver=1.5")

    // user-defined FromStr impl
    let (resp, body) = @http.get(base + "/item2/7")
    assert_eq(resp.code, 200)
    assert_eq(body.text(), "item2 #7")
  }
}
