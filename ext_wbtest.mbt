///|
test "ext_store_set_get" {
  let s = ExtStore::new()
  s.set(RequestId::{  }, "REQ-42")
  s.set(UserId::{  }, "USER-99")

  let req_id : String = s.get(RequestId::{  }) catch { _ => "?" }
  let user_id : String = s.get(UserId::{  }) catch { _ => "?" }

  assert_eq(req_id, "REQ-42")
  assert_eq(user_id, "USER-99")
}

///|
test "ext_store_overwrite" {
  let s = ExtStore::new()
  s.set(RequestId::{  }, "first")
  s.set(RequestId::{  }, "second")

  let req_id : String = s.get(RequestId::{  }) catch { _ => "?" }
  assert_eq(req_id, "second")
}

///|
test "ext_store_remove" {
  let s = ExtStore::new()
  s.set(RequestId::{  }, "REQ-42")
  s.remove(RequestId::{  })

  let req_id : String? = s.try_get(RequestId::{  })
  assert_true(req_id is None)
}

///|
test "exterror missing" {
  let e : ExtError = ExtError::Missing
  assert_true(e is ExtError::Missing)
}

///|
test "exterror decode error" {
  let e : ExtError = ExtError::DecodeError(key="req", msg="not an Int")
  guard e is ExtError::DecodeError(key~, msg~)
  assert_eq(key, "req")
  assert_eq(msg, "not an Int")
}
