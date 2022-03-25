using Sockets
import Sockets: connect, listen

ENV["JULIA_DEBUG"] = Main
using Logging

"Like @async except it prints errors to the terminal. 👶"
macro asynclog(expr)
    quote
        @async begin
            # because this is being run asynchronously, we need to catch exceptions manually
            try
                $(esc(expr))
            catch ex
                bt = stacktrace(catch_backtrace())
                showerror(stderr, ex, bt)
                rethrow(ex)
            end
        end
    end
end


# Two structs

Base.@kwdef struct 🐸Server
    port::UInt16
    accept_task::Task
    tcp_server::Sockets.TCPServer
end

Base.@kwdef struct 🐸ClientConnection
    stream::IO
    outbox::Channel{Any}
    read_task::Task
    write_task::Task
end

const SHUTDOWN = Ref(nothing)

# API: `send_message` and `create_server`

function send_message(client::🐸ClientConnection, message::Union{Vector{UInt8},String})
    put!(client.outbox, message)
end

function create_server(;
    port::Integer,
    on_message::Function = (client, message) -> nothing,
    on_disconnect::Function = (client) -> nothing
)
    # Create a TCP server
    port = UInt16(port)
    tcp_server = listen(port)

    accept_task = @asynclog begin
        while isopen(tcp_server)
            # Wait for a new client to connect, accept the connection and store the stream.
            client_stream = try
                accept(tcp_server)
            catch ex
                if isopen(tcp_server)
                    @warn "Failed to open client stream" exception = (ex, catch_backtrace())
                end
                nothing
            end

            if client_stream isa IO
                client_id = String(rand('a':'z', 6))
                @info "Server: connected" client_id

                # Will hold the client later...
                client_ref = Ref{Union{Nothing,🐸ClientConnection}}(nothing)

                # This task takes items from the outbox and sends them to the client.
                write_task = Task() do
                    while isopen(client_stream)
                        next_msg = take!(client_ref[].outbox)
                        @debug "Message to write!" next_msg
                        if next_msg !== SHUTDOWN && isopen(client_stream)
                            try
                                @debug "writing..."
                                write(client_stream, next_msg)
                            catch ex
                                if isopen(client_stream)
                                    @warn "Server: failed to write to client" client_id exception = (ex, catch_backtrace())
                                end
                            end
                        else
                            break
                        end
                    end
                    @info "Server: client outbox task finished" client_id
                end


                # This task reads from the client and sends the messages to `on_message`.
                read_task = Task() do
                    while isopen(client_stream)
                        incoming = try
                            # Read any available data. This call blocks until data arrives.
                            readavailable(client_stream)
                        catch e
                            @warn "Server: failed to read client data" client_id exception = (e, catch_backtrace())
                            nothing
                        end
                        if !isnothing(incoming) && !isempty(incoming)
                            @debug "Server: message from" client_id length(incoming)
                            try
                                # Let the user handle the message.
                                on_message(client_ref[], incoming)
                            catch e
                                @error "Server: failed to call on_message handler" client_id exception = (e, catch_backtrace())
                            end
                        end
                    end

                    # At this point, the client stream has closed. We send a signal...
                    on_disconnect(client)

                    # ...and we stop the write_task:
                    begin
                        # Clear the queue...
                        while isready(client_ref[].outbox)
                            take!(client_ref[].outbox)
                        end
                        # ...send the stop signal...
                        put!(client_ref[].outbox, SHUTDOWN)
                        # ...wait for the write task to finish.
                        wait(write_task)
                    end

                    @info "Server: stopped reading client" client_id
                end



                client = 🐸ClientConnection(;
                    stream = client_stream,
                    outbox = Channel{Any}(256),
                    read_task,
                    write_task
                )

                client_ref[] = client

                schedule(read_task)
                schedule(write_task)
            end
        end
        @info "Server: stopped accepting"
    end


    return 🐸Server(;
        port,
        accept_task,
        tcp_server
    )
end

"Wrap `expr` in `try ... catch`. The exception is logged and then ignored."
macro trylog(expr, logmsg, loglevel = Logging.Warn)
    quote
        try
            $(esc(expr))
        catch ex
            @logmsg $(loglevel) $(logmsg) exception = (ex, catch_backtrace())
        end
    end
end

"Shut down a server"
function Base.close(server::🐸Server)
    @trylog(
        isopen(server.tcp_server) && close(server.tcp_server),
        "Failed to close server"
    )
    @trylog(
        wait(server.accept_task),
        "Something went wrong with the accept task"
    )
end

Base.wait(server::🐸Server) = wait(server.accept_task)
Base.wait(client::🐸ClientConnection) = begin
    wait(client.read_task)
    wait(client.write_task)
end
Base.isopen(server::🐸Server) = isopen(server.tcp_server)
Base.isopen(client::🐸ClientConnection) = isopen(client.stream)






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


