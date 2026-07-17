///|
pub(all) struct Middleware((Handler) -> Handler) derive(Debug)

///|
fn chain(mws : Array[Middleware], handler : Handler) -> Handler {
  let mut h = handler
  for mw in mws.rev() {
    h = mw(h)
  }
  h
}
