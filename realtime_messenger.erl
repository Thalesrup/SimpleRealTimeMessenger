-module(realtime_messenger).
-behaviour(gen_server).

%% API
-export([start_link/0, init/1, handle_info/2, terminate/2]).

%% TCP API
-export([accept/1, handle_websocket/1, loop/1]).

-define(PORT, 8080).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    {ok, ListenSocket} = gen_tcp:listen(?PORT, [binary, {packet, raw}, {active, false}, {reuseaddr, true}]),
    io:format("WebSocket server listening on port ~p~n", [?PORT]),
    spawn(fun() -> accept(ListenSocket) end),
    {ok, ListenSocket}.

accept(ListenSocket) ->
    {ok, Socket} = gen_tcp:accept(ListenSocket),
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
            gen_tcp:close(Socket)
    end.

loop(Socket) ->
    case gen_tcp:recv(Socket, 0) of
        {ok, Data} ->
            io:format("Received data: ~p~n", [Data]),
            % Decode the WebSocket frame and echo the message
            {ok, Message} = decode_frame(Data),
            io:format("Decoded message: ~p~n", [Message]),
            Response = encode_frame(Message),
            gen_tcp:send(Socket, Response),
            loop(Socket);
        {error, closed} ->
            io:format("Connection closed~n"),
            ok
    end.

create_handshake_response(Key) ->
    Accept = base64:encode(crypto:hash(sha, <<Key/binary, "258EAFA5-E914-47DA-95CA-C5AB0DC85B11">>)),
    "HTTP/1.1 101 Switching Protocols\r\n" ++
    "Upgrade: websocket\r\n" ++
    "Connection: Upgrade\r\n" ++
    "Sec-WebSocket-Accept: " ++ Accept ++ "\r\n\r\n".

parse_http_header(Data) ->
    case re:run(Data, "Sec-WebSocket-Key: ([^\r\n]+)\r\n", [{capture, [1], list}]) of
        {match, [Key]} -> {ok, Key};
        _ -> {error, bad_handshake}
    end.

    decode_frame(<<129, 126, Length:16, Payload/binary>>) ->
        % Mensagens entre 126 e 65535 bytes
        {ok, binary:part(Payload, 0, Length)};
    decode_frame(<<129, 127, Length:64, Payload/binary>>) ->
        % Mensagens maiores que 65535 bytes
        {ok, binary:part(Payload, 0, Length)};
    decode_frame(<<129, Length:7, Payload/binary>>) when Length < 126 ->
        % Mensagens menores que 126 bytes
        {ok, binary:part(Payload, 0, Length)};
    decode_frame(_) ->
        {error, invalid_frame}.

encode_frame(Message) ->
    Length = byte_size(Message),
    if
        Length < 126 ->
            <<129, Length>> ++ Message;
        Length < 65536 ->
            <<129, 126, Length:16>> ++ Message;
        true ->
            <<129, 127, Length:64>> ++ Message
    end.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.
