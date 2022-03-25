import BasicTCP
# ENV["JULIA_DEBUG"] = BasicTCP

import BasicTCP.Server: create_server, send_message


###
# Serialization

import Serialization

function serialize(data)
    io = IOBuffer()
    Serialization.serialize(io, data)
    take!(io)
end

function deserialize(data)
    io = IOBuffer(data)
    Serialization.deserialize(io)
end


###
# Example usage


server = create_server(;
    port = 9092,
    on_message = function(client, message)
        id, ex = deserialize(message)
        # to_send = "Hello, " * String(message)
        # @info "to_send" to_send
        
        result = Core.eval(Main, ex)
        
        send_message(client, serialize((id, result)))
    end,
    on_disconnect = (client) ->
        @info "Server: client disconnected" objectid(client)
)

sleep(30)

close(server)

# You probably dont want to sleep-and-close. Instead, use `wait` to block until the server is closed:
# wait(server)


