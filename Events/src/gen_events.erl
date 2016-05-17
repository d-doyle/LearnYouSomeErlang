-module(gen_events).
-behavior(gen_server).
-export([start/2, start_link/2, cancel/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, code_change/3, terminate/2]).
-record(state, {server, name="", to_go=0}).

%%% User API

%%% Call gen_server start passing in Module, Args, and Options
%%% This function returns {ok, Pid}
start(EventName, DateTime) ->
	gen_server:start(?MODULE, [self(), EventName, DateTime], []).

%%% Call gen_server start link passing in Module, Args, and Options
%%% This function returns {ok, Pid}
start_link(EventName, DateTime) ->
	gen_server:start_link(?MODULE, [self(), EventName, DateTime], []).

%%% Send message to the event process to cancel
cancel(Pid) ->
	%% Monitor in case the process is already dead
	%% We will be notified of any state change
	Ref = erlang:monitor(process, Pid),
	%% Tell gen_server to call handle_cast, passing in ServerRef and Request
	gen_server:cast(Pid, {self(), Ref, cancel}),

	%% Receive messages
	receive
		%% Event process sent back an ok response
		{Ref, ok} ->
			%% Remove the monitor to prevent any additional notifications
			%% and flush any current messages
			erlang:demonitor(Ref, [flush]),
			{Ref, ok};
		%% Monitor sent a down message
		{'DOWN', Ref, process, Pid, Reason} ->
			{Ref, Reason}
	end.

%%% gen_server API

%%% gen_server calls init and passes in the Args
init([Server, EventName, DateTime]) ->
	%% Return ok, State and Timeout to gen_server
	{ok, #state{server=Server, name=EventName, to_go=time_to_go(DateTime)}, time_to_go(DateTime)}.

%%% Replaces loop function, gen_server has the receive block
%%% gen_server calls handle_cast with cancel message
handle_cast({Server, Ref, cancel}, _State) ->
	Server ! {Ref, ok},
	{stop, normal, []};

%%% gen_server calls handle cast with any message
handle_cast(Message, State) ->
	io:format("Handle cast unknown message ~p~n", [Message]),
	{noreply, State}.

%%% gen_server calls handle call with any message
handle_call(Message, _From, State) ->
	io:format("Handle call unknown message ~p~n", [Message]),
	{noreply, State}.

%%% gen_server calls handle info on timeout from value passed on init
handle_info(timeout, S = #state{server=Server}) ->
	Server ! {done, S#state.name},
	{stop, normal, []};

%%% gen_server calls handle info with any message
handle_info(Message, State) ->
	io:format("Handle info unknown message ~p~n", [Message]),
	{noreply, State}.

%%% gen_server calls code change for code updates
code_change(_OldVsn, State, _Extra) ->
	{ok, State}.

%%% gen_server calls terminate when process is stopping
terminate(normal, _State) ->
	ok.

%%% Helper functions

%%% Calculate time to go from the date and time passed to this function
time_to_go(TimeOut={{_,_,_}, {_,_,_}}) ->
	Now = calendar:local_time(),
	ToGo = calendar:datetime_to_gregorian_seconds(TimeOut) - 
		calendar:datetime_to_gregorian_seconds(Now),
	Secs = 
		case ToGo > 0 of
			true -> ToGo;
			false -> 0
		end,
	Secs*1000.

