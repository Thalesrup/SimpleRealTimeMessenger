-module(realtime_messenger).
-behaviour(gen_server).

%% API
-export([start_link/0, init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

%% TCP API
-export([accept/1, handle_websocket/1, loop/1]).

-define(PORT, 8089).

start_link() ->
    io:format("Starting the server...~n"),
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    {ok, ListenSocket} = gen_tcp:listen(?PORT, [
        binary, {packet, raw}, {active, false}, {reuseaddr, true}
    ]),
    io:format("WebSocket server listening on port ~p~n", [?PORT]),
    spawn(fun() -> accept(ListenSocket) end),
    {ok, #{sockets => []}}.  % Estado inicial, lista vazia de sockets

accept(ListenSocket) ->
    {ok, Socket} = gen_tcp:accept(ListenSocket),
    io:format("New client connected: ~p~n", [Socket]),
    gen_server:cast(?MODULE, {new_client, Socket}),
    spawn(fun() -> accept(ListenSocket) end),
    handle_websocket(Socket).

handle_websocket(Socket) ->
    {ok, Data} = gen_tcp:recv(Socket, 0),
    case parse_http_header(Data) of
        {ok, Key} ->
            Response = create_handshake_response(Key),
            gen_tcp:send(Socket, Response),
            loop(Socket);
        _ ->
            io:format("Handshake failed, closing connection: ~p~n", [Socket]),
            gen_server:cast(?MODULE, {remove_client, Socket}),
            gen_tcp:close(Socket)
    end.

loop(Socket) ->
    case gen_tcp:recv(Socket, 0) of
        {ok, Data} ->
            io:format("Received data: ~p~n", [Data]),
            {ok, Message} = decode_frame(Data),
            io:format("Decoded message: ~p~n", [Message]),
            gen_server:cast(?MODULE, {broadcast, Message}),
            loop(Socket);
        {error, closed} ->
            io:format("Connection closed by client: ~p~n", [Socket]),
            gen_server:cast(?MODULE, {remove_client, Socket}),
            ok;
        {error, Reason} ->
            io:format("Unexpected error: ~p, closing connection: ~p~n", [Reason, Socket]),
            gen_server:cast(?MODULE, {remove_client, Socket}),
            gen_tcp:close(Socket)
    end.

handle_cast(Msg, State) ->
    case Msg of
        {new_client, Socket} ->
            NewState = maps:put(sockets, [Socket | maps:get(sockets, State)], State),
            {noreply, NewState};

        {remove_client, Socket} ->
            NewState = maps:put(sockets, lists:delete(Socket, maps:get(sockets, State)), State),
            {noreply, NewState};

        {broadcast, Message} ->
            Sockets = maps:get(sockets, State),
            lists:foreach(fun(Socket) ->
                gen_tcp:send(Socket, encode_frame(Message))
            end, Sockets),
            {noreply, State}
    end.

create_handshake_response(Key) ->
    BinaryKey = list_to_binary(Key),
    Accept = base64:encode(
        crypto:hash(sha, <<BinaryKey/binary, "258EAFA5-E914-47DA-95CA-C5AB0DC85B11">>)
    ),
    Response =
        <<"HTTP/1.1 101 Switching Protocols\r\n", "Upgrade: websocket\r\n",
            "Connection: Upgrade\r\n", "Sec-WebSocket-Accept: ", Accept/binary, "\r\n\r\n">>,
    Response.

parse_http_header(Data) ->
    case re:run(Data, "Sec-WebSocket-Key: ([^\r\n]+)\r\n", [{capture, [1], list}]) of
        {match, [Key]} -> {ok, Key};
        _ -> {error, bad_handshake}
    end.

decode_frame(<<_:4, Opcode:4, Mask:1, Length:7, Rest/binary>>) ->
    case Opcode of
        1 ->
            % Text frame
            case Mask of
                1 ->
                    % Masked frame
                    decode_masked_frame(Length, Rest);
                0 ->
                    % Unmasked frame (not allowed for client-to-server)
                    {error, unmasked_frame}
            end;
        % Handle other frame types (binary, close, ping, pong)
        _ ->
            {error, unsupported_frame_type}
    end;
decode_frame(_) ->
    {error, invalid_frame}.

decode_masked_frame(Length, <<MaskingKey:32, MaskedPayload/binary>>) ->
    % Aplica a chave de máscara ao payload
    Payload = apply_mask(<<MaskingKey:32>>, MaskedPayload),
    {ok, Payload}.

apply_mask(_, <<>>, Acc) -> Acc;
apply_mask(MaskKey, <<P:8, Rest/binary>>, Acc) ->
    <<M1:8, M2:8, M3:8, M4:8>> = MaskKey,
    DecodedByte = P bxor M1,
    NewMaskKey = <<M2, M3, M4, M1>>,  % Rotaciona a chave de máscara
    apply_mask(NewMaskKey, Rest, <<Acc/binary, DecodedByte>>).

apply_mask(MaskKey, MaskedPayload) ->
    apply_mask(MaskKey, MaskedPayload, <<>>).

encode_frame(Message) ->
    Length = byte_size(Message),
    if
        Length < 126 ->
            <<129, Length, Message/binary>>;
        Length < 65536 ->
            <<129, 126, Length:16, Message/binary>>;
        true ->
            <<129, 127, Length:64, Message/binary>>
    end.

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.
