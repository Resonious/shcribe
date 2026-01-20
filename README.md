# scribe

This is a library that dumps HTTP requests and responses to markdown files.

The idea is to add this to your test suite to document real request/response
examples semi-automatically.

[![Package Version](https://img.shields.io/hexpm/v/scribe)](https://hex.pm/packages/scribe)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/scribe/)

```sh
gleam add scribe@1
```
```gleam
import scribe

pub fn main() -> Nil {
  // TODO: An example of the project in use
}
```

Further documentation can be found at <https://hexdocs.pm/scribe>.

## Development

```sh
gleam run   # Run the project
gleam test  # Run the tests
```
