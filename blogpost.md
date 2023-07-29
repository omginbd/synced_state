# Writing an Elixir Library
## Let's learn together

### The Problem or: why spend time on this?
I have been writing a few "CRUD"-type pages at work recently which will likely have multiple people on them at a given time. In an attempt to nip the "my changes were overwritten when someone else saved" bug reports in the bud, I've made a reasonable to effort to ensure the state of all connected clients is updated as it changes. As I've been writing these, I've noticed a pattern emerging: _CRUD operations are a two step process when syncing state across views._

A naive approach might look like:
1. Attempt to perform the CRUD operation
2. Broadcast that a change has been made and that clients should sync their state with the database

The code might look something like this:

```elixir
defmodule MyAppWeb.WidgetsLive do
  use MyAppWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :widgets, MyApp.Widgets.list_widgets())}
  end

  def handle_event("create-widget", widget_attrs, socket) do
    MyApp.Widgets.create_widget(widget_attrs)
    MyAppWeb.Endpoint.broadcast(@topic, "update-state", nil)
    {:noreply, socket}
  end

  def handle_event("update-widget", widget_attrs, socket) do
    MyApp.Widgets.update_widget(widget_attrs)
    MyAppWeb.Endpoint.broadcast(@topic, "update-state", nil)
    {:noreply, socket}
  end

  def handle_event("delete-widget", %{"id" => id}, socket) do
    socket.assigns.widgets
    |> Enum.find(&(&1.id === id))
    |> MyApp.Widgets.delete_widget()
    MyAppWeb.Endpoint.broadcast(@topic, "update-state", nil)
    {:noreply, socket}
  end

  def handle_info(%{topic: @topic, event: "update-state"}, socket) do
    {:noreply, assign(socket, :widgets, MyApp.Widgets.list_widgets)}
  end
end
```

A few questions will lead us to a more performant solution:
- Surely `create_widget` (or whatever context function you call) returns the result of the operation, why not have the executing view just update its state immediately?
- If the result is returned from the context function, why not just broadcast the result (instead of `nil`) and save a database call?
- What if I'm editing a widget, and someone deletes an unrelated widget? Won't my edits will get deleted?


In fact, while simply refreshing the state on every resource operation will technically work, it's a bit like using a jackhammer when you need a nail file. A glaring red flag to look out for when `broadcast`ing state changes is anything that will make a database call. Especially in something like LiveView - where you will have one process for each client connected to the page - anything in your `handle_info` function should be written such that the difference between 1 process and 1,000 processes is minimal.


So, with that in mind, a refactor of the above code could look like:
1. Change the `broadcast`s to be specific about which resource operation has happened, and include the result of the operation.
2. Instead of one `handle_info` which just refreshes the state no matter what happened, write multiple clauses which match on the operation and modify the local state accordingly.


```elixir
defmodule MyAppWeb.WidgetsLive do
  use MyAppWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :widgets, MyApp.Widgets.list_widgets())}
  end

  def handle_event("create-widget", widget_attrs, socket) do
    {:ok, new_widget} = MyApp.Widgets.create_widget(widget_attrs)
    # MyAppWeb.Endpoint.broadcast(@topic, "update-state", nil)
    MyAppWeb.Endpoint.broadcast(@topic, "create-widget", new_widget)
    {:noreply, socket}
  end

  def handle_event("update-widget", widget_attrs, socket) do
    {:ok, updated_widget} = MyApp.Widgets.update_widget(widget_attrs)
    # MyAppWeb.Endpoint.broadcast(@topic, "update-state", nil)
    MyAppWeb.Endpoint.broadcast(@topic, "update-widget", updated_widget)
    {:noreply, socket}
  end

  def handle_event("delete-widget", %{"id" => id}, socket) do
    socket.assigns.widgets
    |> Enum.find(&(&1.id === id))
    |> MyApp.Widgets.delete_widget()
    # MyAppWeb.Endpoint.broadcast(@topic, "update-state", nil)
    MyAppWeb.Endpoint.broadcast(@topic, "delete-widget", id)
    {:noreply, socket}
  end

  def handle_info(%{topic: @topic, event: "create-widget", payload: new_widget}, socket) do
  widgets = [new_widget | socket.assigns.widgets]
    {:noreply, assign(socket, :widgets, widgets)}
  end

  def handle_info(%{topic: @topic, event: "update-widget", payload: %{id: updated_id} = updated_widget}, socket) do
      widgets =
      Enum.map(socket.assigns.widgets, fn
        %Widget{id: ^updated_id} -> updated_widget
        w -> w
      end)

    {:noreply, assign(socket, :widgets, widgets)}
  end

  def handle_info(%{topic: @topic, event: "delete-widget", payload: deleted_id}, socket) do
  widgets = Enum.reject(socket.assigns.widgets, &(&1.id === deleted_id)
    {:noreply, assign(socket, :widgets, widgets)}
  end

  # def handle_info(%{topic: @topic, event: "update-state"}, socket) do
  #   {:noreply, assign(socket, :widgets, MyApp.Widgets.list_widgets)}
  # end

end
```

This is just about as lean as you can get when syncing state across processes. A resource change performed by one process causes a broadcast an some internal processing in all receiving processes. This is great, we've taken our implicit pattern from above and made it explicit: _Each operation happens in two parts, external state is updated in `handle_event` and internal state is updated in `handle_info`._

Not only is turning implicit patterns into explicit logic is one of life's great joys, it's a staple of building a stable system. [State machines](https://en.wikipedia.org/wiki/Finite-state_machine) are a great example of codifying interactions such that you can always be in a predictable state.


## The Problem Part II or: it already works, why are we still spending time on this
Our refactored code is truly a sight to behold; It's simple, clean, and each function is small and focused. Except there's one, teensy tiny, thing that's frustrating about it. If you want to follow what happens when a widget gets deleted, you have to trace a path from `handle_event` -> broadcasting -> `handle_info`. This is less annoying in our toy example where the whole module is just over 50 lines, but real-world modules are rarely this self-contained. At first it might seem like some reorganization is in order, simply move each `handle_info` to be next to its corresponding `handle_event`, yielding:

```elixir
...

  def handle_event("create-widget", widget_attrs, socket) do
    {:ok, new_widget} = MyApp.Widgets.create_widget(widget_attrs)
    # MyAppWeb.Endpoint.broadcast(@topic, "update-state", nil)
    MyAppWeb.Endpoint.broadcast(@topic, "create-widget", new_widget)
    {:noreply, socket}
  end

  def handle_info(%{topic: @topic, event: "create-widget", payload: new_widget}, socket) do
  widgets = [new_widget | socket.assigns.widgets]
    {:noreply, assign(socket, :widgets, widgets)}
  end

...
```

This isn't too bad, it's still two functions but you can at least read those two functions from top to bottom and follow the logic. Except this creates another, teensy tiny, problem. Now if you have a bug where a call is matching the wrong function clause, it's non-trivial to diagnose, as function clauses won't be grouped together. This isn't a problem for Elixir, but the compiler will warn you that this is a bad idea:

```
warning: clauses with the same name and arity (number of arguments) should be grouped together, "def handle_event/3" was previously defined (lib/myapp_web/widgets_live.ex:25)
  lib/myapp_web/widgets_live.ex:45

warning: clauses with the same name and arity (number of arguments) should be grouped together, "def handle_info/2" was previously defined (lib/myapp_web/widgets_live.ex:25)
  lib/myapp_web/widgets_live.ex:45
```

Seems like a catch-22, doesn't it? One way is easier to grok the happy path, one way is easier to debug. This is my day job, so I leave it the way it was because otherwise the build will fail, and call it a day. The code passes review, gets merged and deployed, and wouldn't you know it, it's a hit! People love seeing the page update in real time as edits are made and they immediately know whether or not they need to make changes. So now every page should sync state as it changes, and why not? It's cool when you don't have to refresh your page, and it's only another function or two to make it happen.

But there's a nagging at the back of my brain that calls out. It's the same nagging that promted me to spend time learning and evangelizing [the fastest way to tie your shoes](https://www.youtube.com/watch?v=6cBtqhq5P28), the same nagging that requires that I spend two hours writing a script to save 15 minutes of manual clicking, the same nagging that had me replacing light switches and setting up Home Assistant automations so that when I click play on a movie the lights automatically turn off. This nagging knows that it's not about the time that I won't save, it's about the thrill of the hunt and the satisfaction of feeling like I'm better than the problem. Why should I have to write two functions whenever someone clicks a button? Why is it my responsibility to group functions in the way the compiler likes? Well lucky for me I just read Chris McCord's [Metaprogramming Elixir](https://pragprog.com/titles/cmelixir/metaprogramming-elixir/) and I'm ready to write some code that writes some code, so that I don't have to write that code.

## The Solution or: where we're going, everything's a nail

So we've arrived. We finally have a nail, begging for a hammer. Wouldn't it be great if we could solve our problem by writing something like this?:

```elixir
import SyncState
...

sync_state "create-widget" do
    {:ok, new_widget} = MyApp.Widgets.create_widget(widget_attrs)
    MyAppWeb.Endpoint.broadcast(@topic, "create-widget", new_widget)
    {:noreply, socket, new_widget}
then
  widgets = [new_widget | socket.assigns.widgets]
    {:noreply, assign(socket, :widgets, widgets)}
end

...
```

So that's the dream. Armed with the new folds in our galaxy brain after reading Metaprogramming Elixir, we know we'll need a macro which takes a string, and two "do-blocks" as arguments. A first pass might come out like this:

```elixir
defmodule SyncedState do
  defmacro sync_state(event_name, do: do_block, then: sync_block) do
      quote do
        def handle_event(unquote(event_name), var!(payload), var!(socket)) do
          {resp, socket, result} = unquote(do_block)
          IO.inspect("broadcasting result #{inspect(result)}")
          {resp, socket}
        end

        def handle_info(%{topic: @topic, event: unquote(event_name), payload: var!(result)}, var!(socket)) do
          {resp, socket} = unquote(sync_block)
          {resp, socket}
        end
      end
  end
end
```
_Note: I'm not in the context of phoenix app, so I'm just inspecting instead of actually broadcasting, we'll address this later._

And usage might look like:
```elixir
defmodule TestModule do
  import SyncedState
  @topic Atom.to_string(__MODULE__)

  sync_state "event_name" do
    IO.inspect("Saving to database")
    {:noreply, :socket, :result}
  then
    IO.inspect("Update local state")
    {:noreply, :new_socket}
  end
end
```
_Note: same as above, inspecting instead of actually doing anything for clarity._

Let's fire up iex and see it in action:

`** (FunctionClauseError) no function clause matching in SyncedState.sync_state/2`

Nice. As it turns out, the `do: ... else: ... end` syntax can only be done with a few reserved words: `do, else, catch, rescue, after`. We could support a custom keyword to denote our second step, but that would require a much less convenient syntax:

```elixir
defmodule TestModule do
  import SyncedState
  @topic Atom.to_string(__MODULE__)

  sync_state("event_name",
    do:
      (
        IO.inspect("Saving to database")
        {:noreply, :socket, :result}
      ),
    then:
      (
        IO.inspect("Update local state")
        {:noreply, :new_socket}
      )
  )
end
```

Yuck, the formatter hates that, and so do I. So what if we instead try to leverage one of the supported keywords? By my estimation, `after` is the only one that actually makes sense in this context, as in "Do this thing, then do this _after_." It's probably a stretch, but it keeps the syntax clean :shrug:. Additionally, if the `do` or `after` block doesn't use one of our `var!` variables the compile will complain about unused variables, so let's add implicit usages to avoid that. So after a quick rename, and swapping inspect for an actual broadcast, the final macro looks like this:

```elixir
defmodule SyncedState do
  defmacro sync_state(event_name, do: do_block, after: sync_block) do
      quote do
        def handle_event(unquote(event_name), var!(payload), var!(socket)) do
          _ = payload
          {resp, socket, result} = unquote(do_block)
          @endpoint.broadcast(@topic, unquote(event_name), result)
          {resp, socket}
        end

        def handle_info(%{topic: @topic, event: unquote(event_name), payload: var!(result)}, socket) do
          _ = payload
          unquote(sync_block)
        end
      end
  end
end
```

And sample usage in our example would look like this:
```elixir
defmodule MyAppWeb.WidgetsLive do
  use MyAppWeb, :live_view
  import SyncedState
  @topic Atom.to_string(__MODULE__)
  @endpoint MyAppWeb.Endpoint

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :widgets, MyApp.Widgets.list_widgets())}
  end

  sync_state "create-widget" do
    {:ok, new_widget} = MyApp.Widgets.create_widget(payload)
    {:noreply, socket, new_widget}
  after
    widgets = [result | socket.assigns.widgets]
    {:noreply, assign(socket, :widgets, widgets)}
  end

  sync_state "update-widget" do
    {:ok, updated_widget} = MyApp.Widgets.update_widget(payload)
    {:noreply, socket, updated_widget}
  after
    updated_id = result.id
    widgets =
    Enum.map(socket.assigns.widgets, fn
      %Widget{id: ^updated_id} -> result
      w -> w
    end)

    {:noreply, assign(socket, :widgets, widgets)}
  end

  sync_state "delete-widget" do
    socket.assigns.widgets
    |> Enum.find(&(&1.id === payload.id))
    |> MyApp.Widgets.delete_widget()
    {:noreply, socket, payload.id}
  after
    widgets = Enum.reject(socket.assigns.widgets, &(&1.id === result)
    {:noreply, assign(socket, :widgets, widgets)}
  end
end
```

Success! Now we get to have our cake (updates are synced across open clients) and eat it too (it's clean to read).

## The Solution Part II or: wait wasn't this post supposed to be about writing an Elixir library?


So, a cursory read through the [Elixir Library Guidelines](https://hexdocs.pm/elixir/main/library-guidelines.html) later, we're ready to ignore the [avoid macros](https://hexdocs.pm/elixir/main/library-guidelines.html#avoid-macros) section of the guidelines and create a library that exposes our macro.

One `mix new synced_state`, and a copy paste later, we're in a mix app. Because we're good citizens we start our work by writing a test to definet the behavior we expect when the `sync_state` macro is used. By my estimation it's a good idea to minimize the dependencies of your app, so we'll mock some of the Phoenix behavior instead of making it a dependency of our library. A simple SyncedStateTest might look like this:

```elixir
defmodule SyncedStateTest.DummyEndpoint do
  def broadcast(topic, event_name, result) do
    send(self(), {topic, event_name, result})
  end
end

defmodule SyncedStateTest.DummyModule do
  import SyncedState

  @topic Atom.to_string(__MODULE__)
  @endpoint SyncedStateTest.DummyEndpoint

  sync_state "test-event" do
    socket = Map.put(socket, :new_thing, payload)
    {:noreply, socket, :result}
  after
    socket
  end
end

defmodule SyncedStateTest do
  use ExUnit.Case

  describe "SyncedState" do
    test "sync_state broadcasts a change when an event happens" do
      assert {:noreply, %{new_thing: 1}} =
               SyncedStateTest.DummyModule.handle_event("test-event", 1, %{})

      assert_receive {"Elixir.SyncedStateTest.DummyModule", "test-event", :result}
    end
  end
end
```

A thing of beauty, if I say so myself. We'll try to be good citizens, so let's pretend we've added a moduledoc and a small writup in the readme. Publishing to hex is simple, add [some properties](https://hex.pm/docs/publish#adding-metadata-to-code-classinlinemixexscode) to your `mix.exs` file, and run `mix hex.publish`. Confirm everything looks right, et voilà, this package can be used just like any other!

And that's it! [This package](https://hex.pm/packages/synced_state) is real in case you want to look at the final product. Should you use it in your own code? Probably not. But could you? Yes! If you made it here, thanks for sticking with me. I learned a lot writing this, hopefully you learned something reading it!
