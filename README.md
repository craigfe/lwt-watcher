# Lwt-watcher

Lwt-watcher implements a one-to-many publish/subscribe pattern.

## Use

Lwt-watcher revolves around the notion of an `'a input`: a
publishing/subscription point that carries values of type
`'a`: `create_input: unit -> 'a input`.

Any number of readers can subscribe to the input, each receiving its own
`'a Lwt_stream.t`: `create_stream: 'a input -> 'a Lwt_stream.t * stopper`. The
second returned component is used to unsubscribed from the input:
`shutdown: stopper -> unit`.

Any number of writers can publish a value on the input:
`notify: 'a input -> 'a -> unit`. However, note that if multiple writers publish
values on an input, the library user has to handle any required synchronization.
An input can be closed: `shutdown_input: 'a input -> unit` which in turns closes
all associated streams.

## Installation

```
opam install lwt-watcher
```
