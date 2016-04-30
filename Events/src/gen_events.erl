-module(gen_events).
-behavior(gen_server).
-export([start/2, start_link/2, cancel/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, code_change/3, terminate/2]).
-record(state, {server, name="", to_go=0}).


%%% Spawn a new process calling init, passing in our Pid, with the Event Name and End Date/Time
%%% This function returns the new process's Pid
start(EventName, DateTime) ->
	%% spawn(?MODULE, init, [self(), EventName, DateTime]).
	io:format("calling gen_server start~n", []),
	{ok,Pid} = gen_server:start(?MODULE, [self(), EventName, DateTime], []);
	Pid.

%%% Spawn a linked process calling init, passing in our Pid, with the Event Name and End Date/Time
%%% This function returns the new process's Pid
start_link(EventName, DateTime) ->
	%% spawn_link(?MODULE, init, [self(), EventName, DateTime]).
	io:format("calling gen_server start_link~n", []),
	{ok,Pid} = gen_server:start_link(?MODULE, [self(), EventName, DateTime], []);
	Pid.

%%% Call loop passing in the record parameter
%% init(Server, EventName, DateTime) ->
	%% loop(#state{server=Server, name=EventName, to_go=normalize(time_to_go(DateTime))}).
init([Server, EventName, DateTime]) ->
	%% Return ok, State and Timeout to gen_server
	io:format("gen_server called init~n", []),
	{ok, #state{server=Server, name=EventName, to_go=time_to_go(DateTime)}, time_to_go(DateTime)*1000}.

%% Replaces loop function, gen_server has the receive block
handle_call({_Server, Ref, cancel}, _From, _State) ->
	io:format("gen_server called handle_call, cancel~n", []),
	{stop, {Ref, ok}, []}.

handle_cast(Message, State) ->
	io:format("Handle cast unknown message ~p~n", [Message]),
	{noreply, State}.

handle_info(timeout, S = #state{server=Server}) ->
	io:format("Handle info timeout ~n"),
	Server ! {done, S#state.name},
	{stop, normal, []};

handle_info(Message, State) ->
	io:format("Handle info unknown message ~p~n", [Message]),
	{noreply, State}.

code_change(_OldVsn, State, _Extra) ->
	{ok, State}.

terminate(normal, _State) ->
	ok.

%%% Loop waiting for messages
%%loop(S = #state{server=Server, to_go=[T|Next]}) ->
%%	%% The messages you receive are not related to the function parameters
%%	receive
%%		%% Receive a cancel message, respond with ok, and return (exit)
%%		{Server, Ref, cancel} -> 
%%			Server ! {Ref, ok}
%%	after 
%%		%% After timeout
%%		T * 1000 ->
%%			%% If there are no more timeouts then send done message and return
%%			if Next =:= [] -> 
%%				Server ! {done, S#state.name};
%%			   %% else recursively call loop with remaining time
%%			   Next =/= [] ->
%%				loop(S#state{to_go=Next})
%%			end
%%	end.

%%% Send message to the event process to cancel
cancel(Pid) ->
	%% Monitor in case the process is already dead
	%% We will be notified of any state change
	Ref = erlang:monitor(process, Pid),
	%% Send the cancel message to the event process
	%%Pid ! {self(), Ref, cancel},
	gen_server:call(Pid, {self(), Ref, cancel}).

	%% Receive messages
	%%receive
	%%	%% Event process sent back an ok response
	%%	{Ref, ok} ->
	%%		%% Remove the monitor to prevent any additional notifications
	%%		%% and flush any current messages
	%%		erlang:demonitor(Ref, [flush]),
	%%		{Ref, ok};
	%%	%% Monitor send back a down message
	%%	{'DOWN', Ref, process, Pid, Reason} ->
	%%		{Ref, Reason}
	%%end.

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
	Secs.

%%% Breakup the time to go into a list of 49 day chunks, so "after" can handle it
%%normalize(N) ->
	%%Limit = 49*24*60*60,
	%%[N rem Limit | lists:duplicate(N div Limit, Limit)].

