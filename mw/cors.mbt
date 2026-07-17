///|
/// CORS middleware. Adds Access-Control-* headers to every response.
/// For OPTIONS preflight requests, responds 204 immediately.
pub fn cors(
  allow_origins? : Array[String] = ["*"],
  allow_methods? : Array[String] = [
    "GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS",
  ],
  allow_headers? : Array[String] = ["Content-Type", "Authorization"],
  max_age? : Int = 86400,
) -> @pony.Middleware {
  next => {
    ctx => {
      ctx.set_header("Access-Control-Allow-Origin", allow_origins.join(","))
      ctx.set_header("Access-Control-Allow-Methods", allow_methods.join(","))
      ctx.set_header("Access-Control-Allow-Headers", allow_headers.join(","))
      ctx.set_header("Access-Control-Max-Age", max_age.to_string())

      if ctx.http_method is @pony.HttpMethod::Options {
        ctx.no_content()
        return
      }
      next(ctx)
    }
  }
}
