defmodule SyncedState do
  defmacro sync_state(event_name, do: do_block, after: sync_block) do
    quote do
      def handle_event(unquote(event_name), var!(payload), var!(socket)) do
        _ = var!(payload)
        {resp, socket, result} = unquote(do_block)
        @endpoint.broadcast(@topic, unquote(event_name), result)
        {resp, socket}
      end

      def handle_info(
            %{topic: @topic, event: unquote(event_name), payload: var!(result)},
            var!(socket)
          ) do
        _ = var!(result)
        unquote(sync_block)
      end
    end
  end
end
