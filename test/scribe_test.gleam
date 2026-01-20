import scribe
import gleam/http
import gleam/bit_array
import gleam/json
import gleam/http/response
import gleam/http/request
import gleeunit

pub fn main() -> Nil {
  gleeunit.main()
}

fn json_handler(req: request.Request(BitArray)) -> response.Response(BitArray) {
  let resp = json.object([
    #("your_path", json.string(req.path)),
    #("success", json.bool(True)),
  ])
    |> json.to_string
    |> bit_array.from_string

  response.Response(200, [], resp)
}

pub fn scribe_test() {
  let config = scribe.Config(
    destination: scribe.File("out.md"),
    converter: scribe.as_is(),
  )

  let req_body = json.object([
    #("hello", json.string("world")),
  ])
    |> json.to_string
    |> bit_array.from_string

  let req = request.new()
    |> request.set_method(http.Get)
    |> request.set_path("/test/1")
    |> request.set_header("accept", "application/json")
    |> request.set_body(req_body)

  scribe.call(
    req,
    json_handler,
    with: config,
  )
}
