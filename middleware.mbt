///|
pub(all) struct Middleware((Handler) -> Handler) derive(Debug)

///|
pub extend Middleware with @debug.Debug::{to_repr}

///|
fn chain(mws : Array[Middleware], handler : Handler) -> Handler {
  let mut h = handler
  for mw in mws.rev() {
    h = mw(h)
  }
  h
}
