# SyncedState

[Online Documentation](https://hex.pm/synced_state)

SyncedState is a macro to help you sync state changes across Phoenix LiveViews. It's a wrapper around `handle_event/3` and `handle_info/2`, and the reason for its creation is chronicled [here](./blogpost.md)

## Usage

SyncedState is meant to be used in your liveview module.
First, `import SyncedState`, and define a `@topic` and `@endpoint` module. Also, ensure that your liveview is subscribed to the topic:
```elixir
defmodule MyAppWeb.WidgetLive.Index do
  use MyAppWeb, :live_view

  alias MyApp.Widgets
  alias MyApp.Widgets.Widget

  import SyncedState # import, not use

  @topic Atom.to_string(__MODULE__) # This will be used as the broadcast topic
  @endpoint MyAppWeb.Endpoint # This will be used to broadcast

  @impl true
  def mount(_params, _session, socket) do
    @endpoint.subscribe(@topic) # Make sure you're subscribed
    {:ok, stream(socket, :widgets, Widgets.list_widgets())}
  end

  ...
```

Next, use `sync_state` to define the event name you'd like to use. The `sync_state` macro expects a `do` block, and an `after` block:
```elixir
defmodule MyAppWeb.WidgetLive.Index do

  ...

  sync_state "increment"
  # this block has the event payload in scope as `payload` and the socket in scope, and expects you to return a three element tuple of {handle_event_response, socket, result}
    %{"id" => id} = payload
    widget = Widgets.get_widget!(id)
    {:ok, updated_widget} = Live.Widgets.update_widget(widget, %{count: widget.count + 1})

    {:noreply, socket, updated_widget}
  after
  # this block has the result returned as the third element of the tuple above, and the socket in scope, and expects you to return a two element tuple of {handle_info_response, socket}
  {:noreply, stream_insert(socket, :widgets, result)}
  end
```

It's important to note: the first do block is executed in just the LiveView process which is handling that event, and the `after` block is executed in all LiveView process of the same type, so ideally the `after` block isn't doing anything but updating the socket.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `synced_state` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:synced_state, "~> 0.0.2"}
  ]
end
```
