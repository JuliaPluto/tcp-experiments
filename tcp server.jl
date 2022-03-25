import BasicTCP
ENV["JULIA_DEBUG"] = BasicTCP

import BasicTCP.Server: create_server, send_message


###
# Example usage


server = create_server(;
    port = 9090,
    on_message = (client, message) -> begin
        to_send = "Hello, " * String(message)
        @info "to_send" to_send
        send_message(client, to_send)
    end,
    on_disconnect = (client) ->
        @info "Server: client disconnected" objectid(client)
)

sleep(30)

close(server)

# You probably dont want to sleep-and-close. Instead, use `wait` to block until the server is closed:
# wait(server)


