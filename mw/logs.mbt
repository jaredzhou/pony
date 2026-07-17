///|
/// Request logger middleware. Logs method and path for every request.
pub fn logger() -> @pony.Middleware {
  next => {
    ctx => {
      println("\{"\{ctx.http_method}"} \{"\{ctx.url.path.unwrap_or("")}"}")
      next(ctx)
    }
  }
}
