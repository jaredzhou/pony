///|
/// JWT middleware. Parses `Authorization: Bearer <token>`,
/// verifies the signature, and stores the `sub` claim
/// as user_id via `ctx.set_ext(UserId, ...)`.
pub fn jwt(sig_method : @jwt.SigningMethod) -> @pony.Middleware {
  next => {
    ctx => {
      let token = match ctx.try_header("authorization") {
        Some(auth) if auth.has_prefix("Bearer ") => auth[7:].to_owned()
        _ => {
          next(ctx)
          return
        }
      }
      let parsed = @jwt.parse(token, sig_method) catch {
        _ => {
          next(ctx)
          return
        }
      }
      let (_token, claims) : (@jwt.Token, @jwt.RegisteredClaims) = parsed
      let user_id = claims.sub.unwrap_or("")
      if user_id != "" {
        ctx.set_ext(@pony.UserId::{  }, user_id)
      }
      next(ctx)
    }
  }
}
