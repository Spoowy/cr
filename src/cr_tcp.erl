-module(cr_tcp).
-behaviour(gen_server).
-include("cr.hrl").
-export(?GEN_SERVER).
-compile(export_all).
-record(state, {listener,acceptor,module,name,port}).

handle_info({inet_async,ListSock,Ref,Message},
    #state{listener=ListSock,acceptor=Ref,module=Module,name=Name,port=Port} = State) ->
    {ok,CliSocket} = Message,
    set_sockopt(ListSock, CliSocket),
    {ok, Pid} = cr_server:start_listener(Module,CliSocket),
    gen_tcp:controlling_process(CliSocket, Pid),
    set_socket(Pid, CliSocket),
    Acceptor = case prim_inet:async_accept(ListSock, -1) of
         {ok, NewRef} -> NewRef;
         {error, Reason} ->
              io:format("TCP: Accept Error: ~p~n",[Reason]),
              Reason end,
    {noreply, State#state{acceptor=Acceptor}};

handle_info(_Info, State) -> {noreply, State}.
terminate(_Reason, State) -> gen_tcp:close(State#state.listener), ok.
code_change(_OldVsn, State, _Extra) -> {ok, State}.
handle_call(Request, _From, State) -> {stop, {unknown_call, Request}, State}.
handle_cast(_Msg, State) -> {noreply, State}.

start_link(Name, Port, Module) ->
    gen_server:start_link({local, Name}, ?MODULE, [Name, Port, Module], []).

init([Name, Port, Module]) ->
    process_flag(trap_exit, true),
    Opts = [binary,{packet,0},{reuseaddr,true},{keepalive,true},{backlog,30},{active,false}],
    case gen_tcp:listen(Port, Opts) of
         {ok, Listen_socket} ->
	          {ok, Ref} = prim_inet:async_accept(Listen_socket, -1),
              {ok, #state{ listener = Listen_socket,
                            acceptor = Ref,
                            module = Module,
                            port=Port,
                            name=Name}};
         {error, Reason} -> {stop, Reason} end.

set_sockopt(ListSock, CliSocket) ->
    true = inet_db:register_socket(CliSocket, inet_tcp),
    case prim_inet:getopts(ListSock,[active, nodelay, keepalive, delay_send, priority, tos]) of
         {ok, Opts} -> case prim_inet:setopts(CliSocket, Opts) of
		                    ok -> ok;
                            Error -> gen_tcp:close(CliSocket), Error end;
         Error -> gen_tcp:close(CliSocket), exit({set_sockopt, Error}) end.

set_socket(Pid, Socket) when is_pid(Pid), is_port(Socket) ->
    gen_fsm:send_event(Pid, {socket_ready, Socket}).

reply(Pid, Message) when is_pid(Pid)  ->
    gen_fsm:send_event(Pid, {out, Message}).