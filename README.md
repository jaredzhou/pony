# jaredzhou/pony

A lightweight HTTP web framework for MoonBit, inspired by Go's [Chi](https://github.com/go-chi/chi).

## Installation

Add to your `moon.mod`:

```json
{ "deps": { "jaredzhou/pony": "0.1.0" } }
```

## Quick Start

```moonbit nocheck
///|
fn main {
  let r = Router::Router()

  // GET /ping => 200 "pong"
  r.add(HttpMethod::Get, "/ping", fn(ctx) { ctx.write_text(status_ok, "pong") })

  // GET /users/{id}  => 200 "user: 42"
  // ctx.param raises PonyError if missing — use try_param for Option
  r.add(HttpMethod::Get, "/users/{id}", fn(ctx) {
    let id = ctx.try_param("id").unwrap_or("")
    ctx.write_text(status_ok, "user: \(id)")
  })

  // GET /search?q=pony  => 200 "searching: pony"
  r.add(HttpMethod::Get, "/search", fn(ctx) {
    let q = ctx.try_query("q").unwrap_or("")
    ctx.write_text(status_ok, "searching: \(q)")
  })

  // GET /api/status  => 200 {"status":"ok"}
  r.add(HttpMethod::Get, "/api/status", fn(ctx) {
    ctx.reply_ok({ "status": "ok" })
  })

  // POST /api/items — standard error pattern with to_api_error
  r.add(HttpMethod::Post, "/api/items", async fn(ctx) {
    let req : ItemReq = ctx.json() catch {
      e => {
        ctx.reply_error(to_api_error(PonyError::InvalidArgument(e.to_string())))
        return
      }
    }
    ctx.reply_ok({ "created": true })
  })

  // GET /static/css/app.css  => 200 "file: css/app.css"
  r.add(HttpMethod::Get, "/static/*", fn(ctx) {
    let path = ctx.try_wildcard().unwrap_or("")
    ctx.write_text(status_ok, "file: \(path)")
  })

  // Handler with auth — ctx.header raises PonyError, caught and converted
  r.add(HttpMethod::Get, "/me", async fn(ctx) {
    let user = ctx.header("X-User") catch {
      e => {
        ctx.reply_error(to_api_error(e))
        return
      }
    }
    ctx.reply_ok({ "user": user })
  })

  start("127.0.0.1:3000", r)
}
```

## Features

### Router

- **Radix tree** with priority matching for static, parameter, and wildcard routes
- `{param}` path parameters and `*` wildcard capture
- Route-specific middleware per endpoint
- Sub-router mounting with `mount()`
- Custom 404 and 405 handlers

### Middleware

Built-in via `jaredzhou/pony/mw`:

```moonbit nocheck
r.use_mw(@mw.logger())
r.use_mw(@mw.cors(
  allow_origins=["*"],
  allow_methods=["GET", "POST"],
))
r.use_mw(@mw.jwt(new_hmac_sha256(secret)))
```

| Middleware | Description |
|-----------|-------------|
| `logger()` | Request logging (method, path, status, duration) |
| `cors()` | CORS headers with configurable origins, methods, headers, max-age |
| `jwt(signing_method)` | JWT bearer token auth, stores `sub` claim in context |

### Request Context (`Context`)

Every accessor comes in two forms:

| Raising version (new) | Option version (try_*) | Description |
|---|---|---|
| `ctx.param("id")` | `ctx.try_param("id")` | Path parameter (raises `PonyError::MissingParam`) |
| `ctx.query("search")` | `ctx.try_query("search")` | Query string value (raises `PonyError::MissingQuery`) |
| `ctx.header("Accept")` | `ctx.try_header("Accept")` | Request header (raises `PonyError::MissingHeader`) |
| `ctx.form("name")` | `ctx.try_form("name")` | Form field — async (raises `PonyError::MissingForm`) |
| `ctx.wildcard()` | `ctx.try_wildcard()` | Wildcard path capture (raises `PonyError::MissingParam`) |
| `ctx.json[T]()` | (catch pattern) | JSON body deserialization |
| `ctx.form_file("file")` | `ctx.try_form_file("file")` | Uploaded file header (raises `PonyError::MissingFormFile`) |

**Standard error handling pattern** — the raising methods work with `to_api_error`:

```moonbit nocheck
let user = ctx.header("X-User") catch {
  e => {
    ctx.reply_error(to_api_error(e))
    return
  }
}
```

For cases where a missing value should fall back to a default, use the `try_` variant:

```moonbit nocheck
let q = ctx.try_query("search").unwrap_or("")
let page = ctx.try_query("page").unwrap_or("1")
```

**Response helpers:**

```moonbit nocheck
ctx.set_content_type("application/json")
ctx.write_text(200, "Hello")
ctx.write_json(200, {"key": "value"})
ctx.reply_ok({"status": "ok"})                              // 200 JSON
ctx.reply_error(to_api_error(PonyError::InvalidArgument("bad input"))) // error JSON
ctx.reply_error(ApiError::new(invalid_argument, "bad input"))          // direct ApiError
ctx.redirect("/login")                                         // 302 redirect
ctx.no_content()                                               // 204
```

### Error handling

`PonyError` is the unified error type for context accessors. Use `to_api_error` to convert it:

```moonbit nocheck
pub suberror PonyError {
  MissingParam(String)
  MissingQuery(String)
  MissingForm(String)
  MissingHeader(String)
  MissingExt(String)
  ExtDecodeError(String, String)
  MissingFormFile(String)
  InvalidArgument(String)       // generic 400
  NotFound(String)               // generic 404
  PermissionDenied(String)       // generic 403
}
```

For non-context errors (e.g. failed auth checks, invalid IDs from `parse_int`), construct a `PonyError` variant and pass to `to_api_error`:

```moonbit nocheck
ctx.reply_error(to_api_error(PonyError::InvalidArgument("invalid id")))
ctx.reply_error(to_api_error(PonyError::NotFound("list not found")))
```

For `ctx.json()` parse failures, capture the error and wrap it:

```moonbit nocheck
let req : MyBody = ctx.json() catch {
  e => {
    ctx.reply_error(to_api_error(PonyError::InvalidArgument(e.to_string())))
    return
  }
}
```

### Extension Store

Type-safe key-value store for request-scoped data:

```moonbit nocheck
ctx.set_ext(@pony.RequestId{}, "req-abc")
ctx.set_ext(@pony.UserId{}, "user-42")

let uid = ctx.get_ext(@pony.UserId{})
```

### Header

Full HTTP header management with canonical keys and multi-value support:

```moonbit nocheck
let h = @pony.new()
h.set("Content-Type", "application/json")
h.add("Set-Cookie", "session=abc")
let ct = h.get("Content-Type")  // "application/json"
```

### Server

```moonbit nocheck
let server = @pony.Server::new("127.0.0.1:3000", router)
  .with_timeout(read=5000, write=10000)
server.start()!
```

## License

Apache-2.0
