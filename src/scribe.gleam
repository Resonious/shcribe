import gleam/bool
import gleam/bit_array
import gleam/result
import json_pretty
import gleam/json
import gleam/dynamic/decode
import gleam/list
import gleam/int
import gleam/string
import gleam/option.{Some, None}
import gleam/uri
import gleam/http
import simplifile
import gleam/string_tree
import gleam/http/response
import gleam/http/request
import gleam/io

pub fn main() -> Nil {
  io.println("Hello from scribe!")
}

pub type Destination {
  File(path: String)
  Function(func: fn(string_tree.StringTree) -> Nil)
}

fn write(contents: string_tree.StringTree, to dest: Destination) {
  case dest {
    File(path) -> {
      let assert Ok(_) = simplifile.append(to: path, contents: string_tree.to_string(contents))
      Nil
    }
    Function(func) -> func(contents)
  }
}

fn to_markdown(
  req: request.Request(BitArray),
  resp: response.Response(BitArray),
) -> string_tree.StringTree {
  string_tree.new()
  
  // # GET http://example.com/my/path?my=query
  |> string_tree.append("# ")
  |> string_tree.append(req.method |> http.method_to_string)
  |> string_tree.append(" ")
  |> string_tree.append(req |> request.to_uri |> uri_to_string)
  |> string_tree.append("\n\n")
  // Header-1: Value 1
  |> string_tree.append_tree(headers_to_md(req.headers))
  |> string_tree.append("\n\n")
  // ```\nbody here\n```
  |> string_tree.append_tree(body_to_md(req.body, req.headers |> list.key_find("content-type")))
  // ## Response
  |> string_tree.append("\n## Response\n")
  |> string_tree.append("\nHTTP ")
  |> string_tree.append(resp.status |> int.to_string)
  |> string_tree.append("\n\n")
  |> string_tree.append_tree(headers_to_md(resp.headers))
  |> string_tree.append("\n\n")
  |> string_tree.append_tree(body_to_md(resp.body, resp.headers |> list.key_find("content-type")))
}

fn pretty_json(body: BitArray) -> Result(string_tree.StringTree, Nil) {
  let parsed = json.parse_bits(body, decode.dynamic)
  use dyn <- expect(parsed, or_return: fn() { Error(Nil) })
  use value <- expect(json_pretty.from_dynamic(dyn), or_return: fn() { Error(Nil) })

  json_pretty.pretty_print_tree(value, 0) |> Ok
}

fn headers_to_md(headers: List(#(String, String))) -> string_tree.StringTree {
  use <- bool.lazy_guard(when: list.is_empty(headers), return: fn() { string_tree.from_string("no headers") })

  let header_name_values = list.map(headers, fn(header) {
    let #(name, value) = header

    string_tree.from_string("| ")
    |> string_tree.append(name)
    |> string_tree.append(" | ")
    |> string_tree.append(value)
    |> string_tree.append(" |")
  })
  |> string_tree.join("\n")

  string_tree.from_string("| Name | Value |\n| -------- | -------- |\n")
  |> string_tree.append_tree(header_name_values)
}

fn body_to_md(body: BitArray, content_type: Result(String, Nil)) -> string_tree.StringTree {
  let as_empty = case bit_array.byte_size(body) {
    0 -> Ok(string_tree.from_string("\nno body\n"))
    _ -> Error(Nil)
  }
  use <- result.lazy_unwrap(as_empty)

  let as_json = pretty_json(body)
    |> result.map(fn(json) {
      string_tree.from_string("```json\n")
      |> string_tree.append_tree(json)
      |> string_tree.append("\n```\n")
    })
  use <- result.lazy_unwrap(as_json)

  let as_utf8 = bit_array.to_string(body)
    |> result.map(fn(str) {
      let fmt = case content_type {
        Ok("text/xml") | Ok("application/xml") -> "xml"
        // TODO: there's gotta be more
        _ -> "text"
      }

      string_tree.from_string("```\n")
      |> string_tree.append(fmt)
      |> string_tree.append("\n")
      |> string_tree.append(str)
      |> string_tree.append("\n```\n")
    })
  use <- result.lazy_unwrap(as_utf8)

  let b64 = bit_array.base64_encode(body, True)

  string_tree.from_strings(["```base64\n", b64, "\n```\n"])
}

fn expect(value: Result(a, b), or_return default: fn() -> r, when_ok continue: fn(a) -> r) {
  case value {
    Ok(x) -> continue(x)
    Error(_) -> default()
  }
}

pub type Converter(in, out) {
  Converter(
    request: fn(in) -> BitArray,
    response: fn(out) -> BitArray,
  )
}

fn convert_request(req: request.Request(in), conv: Converter(in, discard)) -> request.Request(BitArray) {
  request.Request(
    method: req.method,
    headers: req.headers,
    body: conv.request(req.body),
    scheme: req.scheme,
    host: req.host,
    port: req.port,
    path: req.path,
    query: req.query,
  )
}

fn convert_response(resp: response.Response(out), conv: Converter(discard, out)) -> response.Response(BitArray) {
  response.Response(
    status: resp.status,
    headers: resp.headers,
    body: conv.response(resp.body),
  )
}

// Same as the official function but no :80 or :443
pub fn uri_to_string(uri: uri.Uri) -> String {
  let parts = case uri.fragment {
    Some(fragment) -> ["#", fragment]
    None -> []
  }
  let parts = case uri.query {
    Some(query) -> ["?", query, ..parts]
    None -> parts
  }
  let parts = [uri.path, ..parts]
  let parts = case uri.host, string.starts_with(uri.path, "/") {
    Some(host), False if host != "" -> ["/", ..parts]
    _, _ -> parts
  }
  let parts = case uri.host, uri.port {
    _, Some(80) | _, Some(443) -> parts
    Some(_), Some(port) -> [":", int.to_string(port), ..parts]
    _, _ -> parts
  }
  let parts = case uri.scheme, uri.userinfo, uri.host {
    Some(s), Some(u), Some(h) -> [s, "://", u, "@", h, ..parts]
    Some(s), None, Some(h) -> [s, "://", h, ..parts]
    Some(s), Some(_), None | Some(s), None, None -> [s, ":", ..parts]
    None, None, Some(h) -> ["//", h, ..parts]
    _, _, _ -> parts
  }
  string.concat(parts)
}

pub fn as_is() -> Converter(BitArray, BitArray) {
  Converter(request: fn(x) { x }, response: fn(x) { x })
}

pub type Config(in, out) {
  Config(destination: Destination, converter: Converter(in, out))
}

pub fn call(
  req: request.Request(in),
  handler: fn(request.Request(in)) -> response.Response(out),
  with config: Config(in, out),
) -> response.Response(out) {
  let resp = handler(req)

  to_markdown(convert_request(req, config.converter), convert_response(resp, config.converter))
  |> write(to: config.destination)

  resp
}

pub fn wrap(
  handler: fn(request.Request(in)) -> response.Response(out),
  with config: Config(in, out),
) -> fn(request.Request(in)) -> response.Response(out) {
  call(_, handler, with: config)
}
