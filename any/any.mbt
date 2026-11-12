// Derived from tonyfettes/any 0.1.5, licensed under Apache-2.0.
// Changes: migrated to current MoonBit syntax and explicit trait extensions.

///|
priv type Object

///|
fn[T] Object::of(value : T) -> Object = "%identity"

///|
fn[T] Object::to(self : Object) -> T = "%identity"

///|
priv trait ToAny {
  fn id() -> Unit = _
  fn get_id(() -> Self) -> TypeId = _
}

///|
impl ToAny with fn id() -> Unit {

}

///|
impl ToAny with fn get_id(_ : () -> Self) -> TypeId {
  Self::id
}

///|
impl[T] ToAny for Ref[T]

///|
fn[T] any_to_string(value : T) -> String = "%any.to_string"

///|
fn[T] type_name(value : () -> T) -> String {
  let string = any_to_string(value)
  guard string is [.. "<obj:() -> ", .. name, '>'] else {
    abort("any.type_name: unexpected any.to_string() format: \{string}")
  }
  name.to_owned()
}

///|
struct Any(TypeInfo, Object)

///|
/// Returns the complete type information for the value stored in this `Any`.
pub fn Any::type_info(self : Any) -> TypeInfo {
  self.0
}

///|
/// Returns the runtime type identifier for the value stored in this `Any`.
pub fn Any::type_id(self : Any) -> TypeId {
  self.0.0
}

///|
/// Returns the human-readable name of the type stored in this `Any`.
pub fn Any::type_name(self : Any) -> String {
  self.0.1
}

///|
#warnings("-unused_constructor")
struct TypeId(() -> Unit)

///|
struct TypeInfo(TypeId, String)

///|
/// Extracts the runtime type identifier from this `TypeInfo`.
pub fn TypeInfo::id(self : TypeInfo) -> TypeId {
  self.0
}

///|
/// Extracts the human-readable type name from this `TypeInfo`.
pub fn TypeInfo::name(self : TypeInfo) -> String {
  self.1
}

///|
let any_id : TypeId = ToAny::get_id((panic : () -> Ref[Any]))

///|
/// Wrap a value of type `T` in an `Any` container.
#as_free_fn
pub fn[T] Any::of(value : T) -> Any {
  let r : Ref[T] = Ref(value)
  let id : TypeId = ToAny::get_id((panic : () -> Ref[T]))
  if physical_equal(id, any_id) {
    let r : Ref[Any] = Object::of(r).to()
    return r.val
  }
  let name : String = type_name((panic : () -> T))
  let info : TypeInfo = TypeInfo(id, name)
  Any(info, Object::of(r))
}

///|
/// Unsafely coerce the underlying value to type `T` without checking.
pub fn[T] Any::unsafe_coerce(self : Any) -> T {
  let r : Ref[T] = self.1.to()
  r.val
}

///|
/// Error raised when attempting to extract a value as an incompatible type.
pub suberror TypeMismatch {
  TypeMismatch(expect~ : TypeInfo, actual~ : TypeInfo)
}

///|
pub impl Show for TypeMismatch with fn output(
  self : TypeMismatch,
  logger : &Logger,
) -> Unit {
  let TypeMismatch(expect~, actual~) = self
  logger.write_string(
    "TypeMismatch: expected type '\{expect.name()}' but found type '\{actual.name()}'",
  )
}

///|
pub extend TypeMismatch with Show::{to_string, output}

///|
pub impl ToJson for TypeMismatch with fn to_json(self : TypeMismatch) -> Json {
  let TypeMismatch(expect~, actual~) = self
  { "TypeMismatch": { "expect": expect.name(), "actual": actual.name() } }
}

///|
pub extend TypeMismatch with ToJson::{to_json}

///|
/// Extract the stored value as type `T` performing a runtime type id check.
pub fn[T] Any::to(self : Any) -> T raise TypeMismatch {
  let id : TypeId = ToAny::get_id((panic : () -> Ref[T]))
  if physical_equal(id, any_id) {
    let r : Ref[T] = Object::of(Ref(self)).to()
    return r.val
  }
  guard physical_equal(self.type_id(), id) else {
    let name = type_name((panic : () -> T))
    raise TypeMismatch::TypeMismatch(expect=TypeInfo(id, name), actual=self.0)
  }
  let r : Ref[T] = self.1.to()
  r.val
}

///|
/// Attempt to extract the stored value as type `T`, returning `None` on mismatch.
pub fn[T] Any::try_to(self : Any) -> T? {
  let id : TypeId = ToAny::get_id((panic : () -> Ref[T]))
  if physical_equal(id, any_id) {
    let r : Ref[T] = Object::of(Ref(self)).to()
    return Some(r.val)
  }
  guard physical_equal(self.type_id(), id) else { return None }
  let r : Ref[T] = self.1.to()
  Some(r.val)
}

///|
/// Conditionally apply `f` if the stored value has type `T`.
pub fn[T, R] Any::map(self : Any, f : (T) -> R raise?) -> Any raise? {
  let id : TypeId = ToAny::get_id((panic : () -> Ref[T]))
  if physical_equal(self.type_id(), id) {
    let r : Ref[T] = self.1.to()
    Any::of(f(r.val))
  } else {
    self
  }
}
