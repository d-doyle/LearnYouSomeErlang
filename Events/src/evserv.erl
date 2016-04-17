-module(evserv).
-compile(export_all).

-record(state, {events, clients}).

-record(event, {name="", description="", pid, timeout={{1970,1,1},{0,0,0}}}).

%%% Spawn a new event server process, register it with the module name, and return the process id
start() ->
	register(?MODULE, Pid=spawn(?MODULE, init, [])),
	Pid.

%%% Spawn and link a new event server process, register it with the module name, and return the process id
start_link() ->
	register(?MODULE, Pid=spawn_link(?MODULE, init, [])),
	Pid.

%%% Terminate the event server
terminate() ->
	?MODULE ! shutdown.

%%% Send message to add Pid as a client/subscriber to the event server
subscribe(Pid) ->
	%% Monitor the event server
	Ref = erlang:monitor(process, whereis(?MODULE)),

	%% Send the subscribe message
	?MODULE ! {self(), Ref, {subscribe, Pid}},

	%% Receive a response from the event server
	receive
		{Ref, ok} ->
			{ok, Ref};
		{'DOWN', Ref, process, _Pid, Reason} ->
			{error, Reason}
	%% Timeout
	after 5000 ->
		      {error, timeout}
	end.

%%% Add a new event to the event server
add_event(Name, Description, TimeOut) ->
	%% Make a new ref
	Ref = make_ref(),

	%% Send the add event message
	?MODULE ! {self(), Ref, {add, Name, Description, TimeOut}},
	
	%% Receive a response from the event server
	receive
		{Ref, Msg} ->
			Msg
	after 5000 ->
		      {error, timeout}
	end.

%%% Cancel an event on the event server
cancel(Name) ->
	%% Make a new ref
	Ref = make_ref(),

	%% Send the cancel event message
	?MODULE ! {self(), Ref, {cancel, Name}},

	%% Receive a response from the event server
	receive
		{Ref, ok} ->
			ok
	after 5000 ->
		      {error, timeout}
	end.

%%% Listen for event done messages from the event server
listen(Delay) ->
	receive
		M = {done, _Name, _Description} ->
			[M | listen(0)]
	after Delay * 1000 ->
		      []
	end.

init() -> 
	%% Loading events from a static file could be done here
	%% You would need to pass an argument to init telling where the
	%% resource to find the events is. Then load it from here.
	%% Another option is to just pass the events straight to the server
	%% through this function.
	loop(#state{events=orddict:new(), clients=orddict:new()}).

%%% Loop (recursively, of course) listening for messages
loop(S = #state{}) ->
	receive
		%% Subscribe message
		{Pid, MsgRef, {subscribe, Client}} ->
			%% Monitor the client process
			Ref = erlang:monitor(process, Client),

			%% Add the client info to the ordered dictionary
			NewClients = orddict:store(Ref, Client, S#state.clients),

			%% Send an ok response
			Pid ! {MsgRef, ok},

			%% Loop passing in the new state
			loop(S#state{clients=NewClients});
		%% Add event message
		{Pid, MsgRef, {add, Name, Description, TimeOut}} ->
			%% Check for valid date time
			case valid_datetime(TimeOut) of
				true ->
					%% Start a new event process
					EventPid = event:start_link(Name, TimeOut),

					%% Add the new event to the events ordered dictionary
					NewEvents = orddict:store(
						      Name, #event{
							       name=Name,
							       description=Description,
							       pid=EventPid,
							       timeout=TimeOut},
						      S#state.events),

					%% Send an ok response
					Pid ! {MsgRef, ok},

					%% Loop passing in the new state
					loop(S#state{events=NewEvents});
				false ->
					%% Date and time for timeout was not valid
					%% Send an error response
					Pid ! {MsgRef, {error, bad_timeout}},

					%% Loop keeping previous state
					loop(S)
			end;
		%% Cancel event message
		{Pid, MsgRef, {cancel, Name}} ->
			%% Find the event in the ordered dictionary
			Events = case orddict:find(Name, S#state.events) of
				{ok, E} ->
					%% Cancel the event
					event:cancel(E#event.pid),

					%% Remove the event from the events ordered dictionary
					orddict:erase(Name, S#state.events);
				error ->
					%% Event not found, just return current events
					S#state.events
			end,

			%% Send an ok response
			Pid ! {MsgRef, ok},

			%% Loop passing in the new state
			loop(S#state{events=Events});
		%% Receive the done message from an Event
		{done, Name} ->
			%% Find the event in the events ordered dictionary
			case ordict:find(Name, S#state.events) of
				{ok, E} ->
					%% Send a done message to each of the clients
					send_to_clients(
					  {done, E#event.name, E#event.description},
					  S#state.clients),

					%% Remove the event from the events ordered dictionary
					NewEvents = orddict:erase(Name, S#state.events),

					%% Loop passing in the new state
					loop(S#state{events=NewEvents});
				error ->
					%% This may happen if we cancel an event and
					%% it fires at the same time
					loop(S)
			end;
		%% Receive a shutdown message and exit
		shutdown ->
			exit(shutdown);
		%% Reveive a down message from one of the clients
		{'DOWN', Ref, process, _Pid, _Reason} ->
			%% Loop and remove the client from the state
			loop(S#state{clients=orddict:erase(Ref, S#state.clients)});
		%% Receive a code change message
		code_change ->
			%% Do an external loop to force the loading of the new code module
			?MODULE:loop(S);
		%% Handle unknown messages by writing out to io
		Unknown ->
			io:format("Unknown message: ~p~n", [Unknown]),
			%% Loop keeping previous state
			loop(S)
	end.

%%% Validate the date and time
valid_datetime({Date,Time}) ->
	try
		calendar:valid_date(Date) andalso valid_time(Time)
	catch
		%% No matching function clause is found when evaluating a function call.
		error:function_clause -> %% not in {{Y,M,D},{H,M,S}} format
			false
	end;

valid_datetime(_) ->
	false.

%%% Validate the time
valid_time({H,M,S}) -> valid_time(H,M,S).
valid_time(H,M,S) when H >= 0, H < 24,
		       M >= 0, M < 60,
		       S >= 0, S < 60 -> true;
valid_time(_,_,_) -> false.

%%% Send a message to all of the clients
send_to_clients(Msg, ClientDict) ->
	orddict:map(fun(_Ref, Pid) -> Pid ! Msg end, ClientDict).

