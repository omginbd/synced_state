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
