///|
/// Compilation test: verify the auth middleware + ext store pattern from README.
/// Uses the existing `UserId` marker from ext.mbt.

///|
test "fn_closure_as_handler_compiles" {
  // Verify arrow function can be used where Handler (async (Context) -> Unit) is expected
  let _h : Handler = (_ctx : Context) => ()
  assert_true(true)
}

///|
test "middleware_pattern_compiles" {
  // Verify fn(next) => (ctx) pattern from README compiles
  let _mw : Middleware = (next : Handler) => (ctx : Context) => next(ctx)
  assert_true(true)
}

///|
test "auth_middleware_full_flow" {
  // Simulate middleware: read header, store in ext
  let ext = ExtStore::new()
  ext.set(UserId::{  }, "user-42")

  // Simulate handler: read ext
  let user_id : String = ext.get(UserId::{  }) catch { _ => "?" }
  assert_eq(user_id, "user-42")
}

///|
test "auth_middleware_missing_ext_try" {
  let ext = ExtStore::new()
  // When no header was sent, try_get returns None
  let got : String? = ext.try_get(UserId::{  })
  assert_true(got is None)
}

///|
test "auth_middleware_missing_ext_raise" {
  let ext = ExtStore::new()
  // When no header was sent, get raises MissingExt
  let result = ext.get(UserId::{  }) catch { e => e }
  guard result is ExtError::Missing
}

///|
test "try_header_returns_none_for_missing" {
  let headers = HttpHeaders::new()
  let got = headers.get("x-user-id")
  assert_eq(got, None)
}

///|
test "try_header_returns_some_for_present" {
  let headers = HttpHeaders::new()
  headers.set("x-user-id", "alice")
  let got = headers.get("x-user-id")
  assert_eq(got, Some("alice"))
}

///|
/// Verify FileHeader struct can be constructed and fields are accessible.
test "file_header_fields" {
  let fh = FileHeader::{
    filename: "photo.png",
    size: 1024,
    content_type: Some("image/png"),
    header: PartHeaders::new(),
    backend: Memory(b"\x00\x01\x02\x03"),
  }
  assert_eq(fh.filename, "photo.png")
  assert_eq(fh.size, 1024)
  assert_eq(fh.content_type, Some("image/png"))
}

///|
test "multipart_form_new_is_empty" {
  let form = MultipartForm::new()
  assert_true(form.field_value("any") is None)
  assert_true(form.file_of("any") is None)
}
