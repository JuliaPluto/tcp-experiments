
import BasicTCP
ENV["JULIA_DEBUG"] = BasicTCP

import BasicTCP.Client: create_connection, send_message

using BenchmarkTools

import Distributed


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

####

const response_channels = Dict{UInt64,Channel{Any}}()


const conn = create_connection(;
    port = 9092,
    on_message = function(data)
        id, msg = deserialize(data)
        put!(response_channels[id], msg)
        # @info "Client: Received: " String(data)
    end
)


function remotecall_eval(conn, code)
    id = rand(UInt64)
    channel = Channel{Any}()
    response_channels[id] = channel
    
    send_message(conn, serialize((id, code)))
    result = take!(channel)
    delete!(response_channels, id)
    return result
end


###
const test_ex = :(first(sqrt.([3,4])))

@info "Our Distributed"

@show(remotecall_eval(conn, :(1 + 1)))

display(@benchmark remotecall_eval(conn, test_ex))

close(conn)



@info "Just the serialization:"


display(@benchmark let
    deserialize(serialize(test_ex))
    deserialize(serialize(6.2))
end)


@info "Distributed"

p = Distributed.addprocs(1)

display(@benchmark Distributed.remotecall_eval(Main, p[1], test_ex))




