-module(gen_evserv).
-behavior(gen_server).
-export([start/0, start_link/0, terminate/0, subscribe/1, add_event/3, cancel/1, listen/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, code_change/3, terminate/2]).
-record(state, {events, clients}).
-record(event, {name="", description="", pid, timeout={{1970,1,1},{0,0,0}}}).

%%% User API

%%% Call gen_server start passing in Module, Args, and Options, 
%%%  register it with the module name, and return the process id
start() ->
	{ok,Pid} = gen_server:start(?MODULE, [], []),
	register(?MODULE, Pid),
	Pid.

%%% Call gen_server start_link passing in Module, Args, and Options, 
%%% register it with the module name, and return the process id
start_link() ->
	{ok,Pid} = gen_server:start_link(?MODULE, [], []),
	register(?MODULE, Pid),
	Pid.

%%% Terminate the event server
terminate() ->
	?MODULE ! shutdown.

%%% Send message to add Pid as a client/subscriber to the event server
subscribe(Pid) ->
	%% Monitor the event server
	Ref = erlang:monitor(process, whereis(?MODULE)),

	%% Send the subscribe message
	gen_server:call(?MODULE, {self(), Ref, {subscribe, Pid}}).

%%% Add a new event to the event server
add_event(Name, Description, TimeOut) ->
	%% Make a new ref
	Ref = make_ref(),

	%% Send the add event message
	gen_server:call(?MODULE, {self(), Ref, {add, Name, Description, TimeOut}}),
	
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
	gen_server:call(?MODULE, {self(), Ref, {cancel, Name}}),

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

%%% gen_server calls init and passes in the Args
init([]) -> 
	%% Loading events from a static file could be done here
	%% You would need to pass an argument to init telling where the
	%% resource to find the events is. Then load it from here.
	%% Another option is to just pass the events straight to the server
	%% through this function.
	io:format("gen_server called init~n", []),
	%% Return ok and State to gen_server
	{ok, #state{events=orddict:new(), clients=orddict:new()}}.

handle_call({_Pid, MsgRef, {subscribe, Client}}, _From, S = #state{}) ->
	%% Monitor the client process
	Ref = erlang:monitor(process, Client),

	%% Add the client info to the ordered dictionary
	NewClients = orddict:store(Ref, Client, S#state.clients),

	%% Send an ok response
	%% Pid ! {MsgRef, ok},

	%% Reply and return new state
	{reply, {MsgRef, ok}, S#state{clients=NewClients}};
	
%%% Add event message
handle_call({_Pid, MsgRef, {add, Name, Description, TimeOut}}, _From, S = #state{}) ->
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
			%% Pid ! {MsgRef, ok},

			%% Reply and return new state
			{reply, {MsgRef, ok}, S#state{events=NewEvents}};
		false ->
			%% Date and time for timeout was not valid
			%% Send an error response
			%% Pid ! {MsgRef, {error, bad_timeout}},

			{reply, {MsgRef, {error, bad_timeout}}, S}
	end;

%% Cancel event message
handle_call({_Pid, MsgRef, {cancel, Name}}, _From, S = #state{}) ->
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
	%% Pid ! {MsgRef, ok},

	%% Loop passing in the new state
	{reply, {MsgRef, ok}, S#state{events=Events}};

%%% Receive the done message from an Event
handle_call({done, Name}, _From, S=#state{}) ->
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
			{noreply, S#state{events=NewEvents}};
		error ->
			%% This may happen if we cancel an event and
			%% it fires at the same time
			{noreply, S}
	end.

%%% Receive a shutdown message and exit
handle_cast(shutdown, _State) -> 
	%% exit(shutdown).
	{stop, normal, []};

%%% Reveive a down message from one of the clients
handle_cast({'DOWN', Ref, process, _Pid, _Reason}, S=#state{}) ->
	%% Loop and remove the client from the state
	{noreply, S#state{clients=orddict:erase(Ref, S#state.clients)}}.

%%% Receive a code change message
code_change(_OldVsn, State, _Extra) ->
	{ok, State}.

%%% gen_server calls handle info with any message
handle_info(Message, State) ->
	io:format("Handle info unknown message ~p~n", [Message]),
	{noreply, State}.

%%% Validate the date and time
%%% gen_server calls terminate when process is stopping
terminate(normal, _State) ->
	ok.

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

