FROM erlang:28

WORKDIR /app

# Copy the estun library
COPY _build/default/lib/estun /app/estun
COPY include /app/estun/include
COPY examples/docker_p2p/*.erl /app/

# Compile the modules
RUN erlc -pa /app/estun/ebin -I /app/estun/include \
    /app/docker_signaling.erl \
    /app/docker_peer.erl

CMD ["erl", "-pa", "/app/estun/ebin", "-pa", "/app", "-noshell"]
