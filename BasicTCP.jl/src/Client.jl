module Client

using Sockets
import Sockets: connect
using Logging

Base.@kwdef struct 🐸ServerConnection
    stream::IO
    read_task::Task
end

# API: `send_message` and `create_server`

function send_message(sc::🐸ServerConnection, message::Union{Vector{UInt8},String})
    write(sc.stream, message)
end

function send_message(writer::Function, sc::🐸ServerConnection)
    # TODO: writing and reading TCP should have a message boundary to mark the end of a message. Right now the end is determined using timing, which does not work in lots of cases.
    # See `message_handler_loop` in the Distributed source code for an example.
    
    writer(sc.stream)
end

function create_connection(;
    port::Integer,
    on_message::Function
)
    stream = connect(port)
    @info "Client: Connected!"

    read_task = @async try
        while isopen(stream) && isreadable(stream)
            incoming = readavailable(stream)
            if !isempty(incoming)
                on_message(incoming)
            end
        end
        @info "Client: stopped reading"
    catch e
        @error "Client: read error" exception = (e, catch_backtrace())
    end


    return 🐸ServerConnection(;
        stream,
        read_task
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
function Base.close(server::🐸ServerConnection)
    @trylog(
        isopen(server.stream) && close(server.stream),
        "Failed to close connection"
    )
    @trylog(
        wait(server.read_task),
        "Something went wrong with the read task"
    )
end
Base.wait(sc::🐸ServerConnection) = wait(sc.read_task)
Base.isopen(sc::🐸ServerConnection) = isopen(sc.stream)





end