# jaredzhou/pony

A lightweight HTTP web framework for MoonBit, inspired by Go's [Chi](https://github.com/go-chi/chi).

## Installation

```bash
moon add jaredzhou/pony
```

## Quick Start

```moonbit nocheck
///|
fn main {
  let r = Router::Router()

  // GET /hello  => 200 "Hello, world!"
  r.add(HttpMethod::Get, "/hello", ctx => {
    ctx.write_text(status_ok, "Hello, world!")
  })

  // GET /greet/pony  => 200 "Hello, pony!"
  r.add(HttpMethod::Get, "/greet/{name}", ctx => {
    let name = ctx.try_param("name").unwrap_or("stranger")
    ctx.write_text(status_ok, "Hello, \(name)!")
  })

  start("127.0.0.1:3000", r)
}
```

## Features

### Router

The router is a radix tree with priority matching. Routes can be registered for specific HTTP methods or all methods via `any()`.

```moonbit nocheck
let r = Router::Router()

// Static route — exact path match
r.add(HttpMethod::Get, "/ping", pong_handler)

// Path parameter {param} — matches a single segment
r.add(HttpMethod::Get, "/users/{id}", user_handler)

// Wildcard * — matches everything after the prefix
r.add(HttpMethod::Get, "/static/*", static_handler)

// Multiple parameters in one pattern
r.add(HttpMethod::Get, "/users/{userId}/posts/{postId}", post_handler)

// Match all HTTP methods
r.any("/health", health_handler)

// Route-specific middleware (applied before the handler)
r.add(
  HttpMethod::Get,
  "/admin",
  mws=[admin_auth],
  admin_handler,
)

// Sub-router mounting — all routes under /api/v1
let api = Router::Router()
api.add(HttpMethod::Get, "/status", status_handler)
r.mount("/api/v1", api)

// Custom 404 / 405 handlers
r.set_not_found(ctx => {
  ctx.reply_error(ApiError::new(not_found, "page not found"))
})
r.set_method_not_allowed(ctx => {
  ctx.reply_error(ApiError::new(method_not_allowed, "method not allowed"))
})
```

| Method | Description |
|---|---|
| `r.add(method, pattern, handler)` | Add a route for a specific HTTP method |
| `r.any(pattern, handler)` | Match all HTTP methods |
| `r.mount(prefix, sub_router)` | Mount a sub-router under a prefix |
| `r.use_mw(middleware)` | Add global middleware |
| `r.set_not_found(handler)` | Custom 404 handler |
| `r.set_method_not_allowed(handler)` | Custom 405 handler |

**Route patterns:**

| Pattern | Example | Matches |
|---|---|---|
| Static | `/ping` | `/ping` only |
| Param `{name}` | `/users/{id}` | `/users/42`, `/users/alice` |
| Wildcard `*` | `/static/*` | `/static/css/app.css`, `/static/js/main.js` |

### Server

```moonbit nocheck
let server = @pony.Server::new("127.0.0.1:3000", router)
  .with_timeout(read=5000, write=10000)
server.start()!
```

### Request Context

Every accessor comes in two forms: a raising version and a `try_` variant that returns `Option`.

Raising versions are generic over the `@pony.FromStr` trait — annotate the target type and the value is parsed for you. A missing key raises `MissingParam`/`MissingQuery`/`MissingHeader`/`MissingForm`; a present value that fails to parse raises `InvalidValue` (mapped to HTTP 400). Catch and pass directly to `reply_error`:

```moonbit nocheck
///|
let id : Int = ctx.param("id") catch {
  e => {
    ctx.reply_error(e)
    return
  }
}

///|
let token : String = ctx.header("Authorization") catch {
  e => {
    ctx.reply_error(e)
    return
  }
}

///|
let page : Int = ctx.query("page") catch { _ => 1 }
```

Built-in `FromStr` impls: `String` (identity), `Int`, `Int64`, `UInt`, `UInt64`, `Double`, `Bool`. Implement it for your own types to use them with the typed accessors:

```moonbit nocheck
///|
struct UserId(Int)

///|
pub impl @pony.FromStr for UserId with fn from_str(s) {
  UserId(@pony.FromStr::from_str(s))
}

///|
let uid : UserId = ctx.param("id") catch { ... }
```

Use the `try_` variant when a default fallback makes sense — it always returns the raw `String?`:

```moonbit nocheck
///|
let page = ctx.try_param("page").unwrap_or("1")

///|
let q = ctx.try_query("q").unwrap_or("")

///|
let name = ctx.try_form("name").unwrap_or("")
```

**JSON body:**

```moonbit nocheck
///|
struct LoginReq {
  username : String
  password : String
} derive(FromJson)

///|
let req : LoginReq = ctx.json() catch {
  _ => {
    ctx.reply_error(PonyError::InvalidArgument("invalid JSON body"))
    return
  }
}
```

**Response helpers:**

```moonbit nocheck
ctx.set_content_type("application/json")
ctx.write_text(status_ok, "Hello")
ctx.write_json(status_ok, {"key": "value"})
ctx.reply_ok({"status": "ok"})                                  // 200 JSON
ctx.reply_error(PonyError::InvalidArgument("bad input"))         // 400 JSON
ctx.reply_error(PonyError::NotFound("not found"))               // 404 JSON
ctx.reply_error(ApiError::new(invalid_argument, "bad input"))   // direct ApiError
ctx.redirect("/login")                                             // 302
ctx.no_content()                                                   // 204
```

| Raising version (`T : FromStr`) | Option version (`String?`) | Description |
|---|---|---|
| `ctx.param("id")` | `ctx.try_param("id")` | Path parameter |
| `ctx.query("q")` | `ctx.try_query("q")` | Query string value |
| `ctx.header("Accept")` | `ctx.try_header("Accept")` | Request header |
| `ctx.form("name")` | `ctx.try_form("name")` | Form field (async) |
| `ctx.wildcard()` | `ctx.try_wildcard()` | Wildcard path capture (`String`) |
| `ctx.json[T]()` | — | JSON body deserialization |
| `ctx.form_file("file")` | `ctx.try_form_file("file")` | Uploaded file header |

### Extension Store

Type-safe key-value store for passing request-scoped data between middleware and handlers. Keys are marker types (empty structs), values are inferred from usage.

**Custom auth middleware example:**

```moonbit nocheck
///|
// Marker type — an empty struct used as a type-safe key
struct UserId {}

///|
// Middleware: extract user_id from header and store in context
fn auth_middleware(next : Handler) -> Handler {
  ctx => {
    match ctx.try_header("X-User-Id") {
      Some(user_id) => ctx.set_ext(UserId{}, user_id)
      None => {
        ctx.reply_error(ApiError::new(unauthenticated, "missing X-User-Id header"))
        return
      }
    }
    next(ctx)
  }
}

///|
fn main {
  let r = Router::Router()
  r.use_mw(auth_middleware)

  r.add(HttpMethod::Get, "/me", ctx => {
    let user_id : String = ctx.get_ext(UserId{}) catch {
      e => {
        ctx.reply_error(e)
        return
      }
    }
    ctx.reply_ok({ "user_id": user_id })
  })

  start("127.0.0.1:3000", r)
}
```

**Built-in markers** (from `@pony`):

```moonbit nocheck
ctx.set_ext(@pony.RequestId{}, "req-abc")
ctx.set_ext(@pony.UserId{}, "user-42")

let uid = ctx.get_ext(@pony.UserId{}) catch {
  e => {
    ctx.reply_error(e)
    return
  }
}
```

| Method | Description |
|---|---|
| `ctx.set_ext(marker, value)` | Store a typed value |
| `ctx.get_ext(marker)` | Retrieve, raises `PonyError::MissingExt` if absent |
| `ctx.try_get_ext(marker)` | Retrieve, returns `Option` |
| `ctx.remove_ext(marker)` | Remove a stored value |

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
| `jwt(signing_method)` | JWT bearer token auth, stores `sub` claim via `set_ext(UserId, …)` |

### Error handling

`PonyError` is the unified error type for context accessors. It implements `ToApiError`, so you can pass it directly to `reply_error`:

```moonbit nocheck
///|
pub suberror PonyError {
  MissingParam(String)
  MissingQuery(String)
  MissingForm(String)
  MissingHeader(String)
  MissingExt(String)
  ExtDecodeError(String, String)
  MissingFormFile(String)
  InvalidArgument(String) // generic 400
  NotFound(String) // generic 404
  PermissionDenied(String) // generic 403
}
```

For non-context errors, construct a `PonyError` variant and pass directly to `reply_error`:

```moonbit nocheck
ctx.reply_error(PonyError::InvalidArgument("invalid id"))
ctx.reply_error(PonyError::NotFound("list not found"))
ctx.reply_error(PonyError::PermissionDenied("access denied"))
```

**Custom error types** — implement `ToApiError` for your own error types:

```moonbit nocheck
///|
pub impl @pony.ToApiError for MyError with fn to_api_error(self : MyError) -> @pony.ApiError {
  match self {
    MyError::NotFound(m) => @pony.ApiError::new(@pony.not_found, m)
    MyError::Forbidden(m) => @pony.ApiError::new(@pony.permission_denied, m)
  }
}

// Now you can pass MyError directly:
ctx.reply_error(my_error)
```

### File Upload

Handle multipart file uploads with `parse_multipart_form`, then access files via `form_file` and fields via `form`:

```moonbit nocheck
///|
r.add(HttpMethod::Post, "/upload", async ctx => {
  // Parse the multipart body (call once per request)
  ctx.parse_multipart_form()!

  // Read regular form fields
  let title : String = ctx.form("title") catch {
    e => { ctx.reply_error(e); return }
  }

  // Access uploaded files
  let file = ctx.form_file("avatar") catch {
    e => { ctx.reply_error(e); return }
  }

  // File metadata available immediately
  println("received: \{file.filename} (\{file.size} bytes, \{file.content_type})")

  // Read file content (async)
  let data = file.bytes()

  ctx.reply_ok({
    "title": title,
    "filename": file.filename,
    "size": file.size,
  })
})
```

| Method | Returns | Description |
|---|---|---|
| `ctx.parse_multipart_form()` | `Unit` | Parse multipart body (call before accessing files/fields) |
| `ctx.form("key")` | `T raise PonyError` | Form field value, parsed via `FromStr` (use `try_form` for raw `String?`) |
| `ctx.form_file("key")` | `FileHeader raise PonyError` | Single uploaded file (use `try_form_file` for `Option`) |
| `ctx.form_files("key")` | `Array[FileHeader]` | All files for a multi-file field |
| `file.bytes()` | `Bytes` | Read full file content |
| `file.filename` | `String` | Original filename |
| `file.size` | `Int64` | Uncompressed file size |
| `file.content_type` | `String?` | MIME type (e.g. `"image/png"`) |
| `file.path()` | `String?` | Temp file path if spilled to disk |

## License

Apache-2.0
