import BasicTCP
ENV["JULIA_DEBUG"] = BasicTCP

import BasicTCP.Client: create_connection, send_message




###
# Example usage


conn = create_connection(;
    port = 9090,
    on_message = data -> begin
        @info "Client: Received: " String(data)
    end
)



sleep(1)

send_message(conn, "Hi!!")
sleep(1)

send_message(conn, "fonsi")
sleep(1)

send_message(conn, "Hannesssss")
sleep(1)

close(conn)


