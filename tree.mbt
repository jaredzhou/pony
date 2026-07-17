///|
enum NodeType {
  // Static(prefix)
  Static(String)
  // Param(name, tail_char)
  Param(String, Char)
  // Wildcard is always * and at the end of the pattern
  Wildcard
} derive(Debug)

///|
fn NodeType::prefix(self : NodeType) -> String {
  match self {
    Static(s) => s
    Param(_, _) => ""
    Wildcard => ""
  }
}

///|
pub impl Show for NodeType with fn to_string(self : NodeType) -> String {
  match self {
    Static(s) => "Static(" + s + ")"
    Param(name, tail) => "Param(" + name + "," + tail.to_string() + ")"
    Wildcard => "*"
  }
}

///|
struct Endpoint {
  name : String
  handler : Handler
  pattern : String
  path_params : Array[String]
} derive(Debug)

///|
fn Endpoint::to_paramKV_array(
  self : Endpoint,
  values : Array[String],
) -> Array[ParamKV] {
  self.path_params.zip(values).map(kv => ParamKV(kv.0, kv.1))
}

///|
struct Node {
  mut node_type : NodeType
  mut children_static : Array[Node]
  mut children_param : Array[Node]
  mut child_wildcard : Node?
  mut endpoints : Map[HttpMethod, Endpoint]
} derive(Debug)

///|
pub impl Show for Node with fn to_string(self : Node) -> String {
  let sb = StringBuilder::new()
  fn render(node : Node, indent : String, is_last : Bool, prefix : String) {
    sb.write_string(indent)
    sb.write_string(prefix)
    let node_str = if node.node_type.to_string() == "" {
      "root"
    } else {
      node.node_type.to_string()
    }
    sb.write_string(node_str)
    for m, ep in node.endpoints {
      sb.write_string(" " + m.to_string())
      sb.write_string("(")
      sb.write_string(ep.pattern)
      sb.write_string(")")
    }
    sb.write_string("\n")
    let new_indent = indent + (if is_last { "    " } else { "│   " })
    let children : Array[(Node, String)] = []
    for c in node.children_static {
      children.push((c, "├── "))
    }
    for p in node.children_param {
      children.push((p, "p── "))
    }
    match node.child_wildcard {
      Some(w) => children.push((w, "w── "))
      None => ()
    }
    let len = children.length()
    for i, pair in children {
      let (child, p) = pair
      let is_last_child = i == len - 1
      let actual_prefix = if is_last_child {
        if p == "├── " {
          "└── "
        } else {
          p
        }
      } else {
        p
      }
      render(child, new_indent, is_last_child, actual_prefix)
    }
  }

  render(self, "", true, "")
  sb.to_string()
}

///|
fn Node::get_handler(self : Node, meth : HttpMethod) -> Endpoint? {
  if self.endpoints.get(meth) is Some(ep) {
    return Some(ep)
  }
  return self.endpoints.get(HttpMethod::Any)
}

///|
fn Node::insert(
  self : Node,
  http_method : HttpMethod,
  pattern : String,
  name? : String = "",
  handler : Handler,
) -> Unit raise RouterError {
  let path_params : Array[String] = []
  for node = self, remain = pattern[:] {
    if remain == "" {
      node.set_endpoint(http_method, pattern, handler, path_params, name~)
      break
    } else if remain is ['{', .. remaining] {
      guard remaining.find("}") is Some(end_idx) else {
        raise RouterError::InvalidPattern(
          http_method=http_method.to_string(),
          path=pattern,
          reason="unclosed path parameter",
        )
      }
      let param_name = remaining[:end_idx].to_owned()
      path_params.push(param_name)
      //params is within path segemnt, if no tail, it is until "/"
      let tail : Char = remaining.get_char(end_idx + 1).unwrap_or('/')
      let mut next_node : Node? = None
      for p in node.children_param {
        if p.node_type is Param(_, t) && t == tail {
          next_node = Some(p)
          break
        }
      }
      let next_node = match next_node {
        Some(param_node) => param_node
        None => {
          let new_node = Node::{
            node_type: Param(param_name, tail),
            children_static: [],
            children_param: [],
            child_wildcard: None,
            endpoints: Map([]),
          }
          if tail == '/' {
            node.children_param.push(new_node)
          } else {
            node.children_param.insert(0, new_node)
          }
          new_node
        }
      }
      continue next_node, remaining[end_idx + 1:]
    } else if remain is ['*', .. remaining] {
      guard remaining == "" else {
        raise RouterError::InvalidPattern(
          http_method=http_method.to_string(),
          path=pattern,
          reason="* should be at the end of the pattern",
        )
      }
      path_params.push("*")
      let next_node = match node.child_wildcard {
        Some(wildcard_node) => wildcard_node
        None => {
          let new_node = Node::{
            node_type: Wildcard,
            children_static: [],
            children_param: [],
            child_wildcard: None,
            endpoints: Map([]),
          }
          node.child_wildcard = Some(new_node)
          new_node
        }
      }
      continue next_node, remaining
    } else {
      let rest = remain
      match node.find_common_prefix(rest) {
        Some((child, common)) => {
          let child_prefix = child.node_type.prefix()
          if common < child_prefix.length() {
            // Split the child node:
            // 1. Create a new node for the suffix
            let suffix_node = Node::{
              node_type: Static(child_prefix[common:].to_owned()),
              children_static: child.children_static,
              children_param: child.children_param,
              child_wildcard: child.child_wildcard,
              endpoints: child.endpoints,
            }
            // 2. Update the existing child to be the common prefix
            child.node_type = Static(child_prefix[:common].to_owned())
            child.children_static = [suffix_node]
            child.children_param = []
            child.child_wildcard = None
            child.endpoints = Map([])
            continue child, rest[common:]
          } else {
            // Fully matched child prefix, move into it
            continue child, rest[common:]
          }
        }
        None => {
          let static_len = match rest.find_by(c => c == '{' || c == '*') {
            Some(idx) => idx
            None => rest.length()
          }
          let new_node = Node::{
            node_type: Static(rest[:static_len].to_owned()),
            children_static: [],
            children_param: [],
            child_wildcard: None,
            endpoints: Map([]),
          }
          node.children_static.push(new_node)
          continue new_node, rest[static_len:]
        }
      }
    }
  }
}

///|

///|
fn Node::dfs(
  self : Node,
  meth : HttpMethod,
  remain : StringView,
  param_values : Array[String],
) -> RouteResult {
  if remain == "" {
    if self.get_handler(meth) is Some(ep) {
      return RouteResult::Found(ep, param_values)
    }
    // Path matches but wrong method
    if !self.endpoints.is_empty() {
      return RouteResult::MethodNotAllowed
    }
    if self.child_wildcard is Some(wildcard_node) &&
      wildcard_node.get_handler(meth) is Some(ep) {
      param_values.push(remain.to_owned())
      return RouteResult::Found(ep, param_values)
    }
    return RouteResult::NotFound
  }
  let mut has_method_not_allowed = false
  // Try static children
  for child in self.children_static {
    if child.node_type is Static(prefix) {
      if remain.has_prefix(prefix) {
        let next_remain = remain[prefix.length():]
        match child.dfs(meth, next_remain, param_values) {
          Found(_, _) as found => return found
          MethodNotAllowed => has_method_not_allowed = true
          _ => ()
        }
      }
    }
  }
  // Try param children
  for child in self.children_param {
    if child.node_type is Param(_, tail) {
      // find the param value until tail char or "/"
      let mut split_idx = remain.length()
      if remain.find("/") is Some(idx) {
        split_idx = idx
      }
      if remain.find(tail.to_string()) is Some(idx) && idx < split_idx {
        split_idx = idx
      }
      let param_value = remain[:split_idx].to_owned()
      let next_remain = remain[split_idx:]
      param_values.push(param_value)
      match child.dfs(meth, next_remain, param_values) {
        Found(_, _) as found => return found
        MethodNotAllowed => has_method_not_allowed = true
        _ => ()
      }
      let _ = param_values.pop()
    }
  }
  // Try wildcard child
  if self.child_wildcard is Some(wildcard_node) &&
    wildcard_node.get_handler(meth) is Some(ep) {
    param_values.push(remain.to_owned())
    return RouteResult::Found(ep, param_values)
  }
  if has_method_not_allowed {
    return RouteResult::MethodNotAllowed
  }
  RouteResult::NotFound
}

///|
/// find_route searches for a matching route in the node tree
/// path here is the remaining path to match, so it find_route in all child nodes
/// first static children, then param children, then wildcard child
fn Node::route(self : Node, meth : HttpMethod, path : String) -> RouteResult {
  self.dfs(meth, path[:], [])
}

///|
fn common_prefix_len(s1 : String, s2 : StringView) -> Int {
  let len = if s1.length() < s2.length() { s1.length() } else { s2.length() }
  for i = 0; i < len; i = i + 1 {
    if s1.get_char(i) != s2.get_char(i) {
      return i
    }
  }
  len
}

///|
fn Node::find_common_prefix(self : Node, str : StringView) -> (Node, Int)? {
  for child in self.children_static {
    if child.node_type is Static(prefix) {
      let common = common_prefix_len(prefix, str)
      if common > 0 {
        return Some((child, common))
      }
    }
  }
  None
}

///|
fn Node::set_endpoint(
  self : Node,
  http_method : HttpMethod,
  pattern : String,
  name? : String = "",
  handler : Handler,
  path_params : Array[String],
) -> Unit {
  let ep = Endpoint::{ name, handler, pattern, path_params }
  self.endpoints.set(http_method, ep)
}
