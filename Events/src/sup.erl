-module(sup).
-export([start/2, start_link/2, init/1, loop/1]).

%%% Spawn a new supervisor process for this module with arguments
start(Mod,Args) ->
	spawn(?MODULE, init, [{Mod, Args}]).

%%% Spawn a new linked supervisor process for this module with arguments
start_link(Mod,Args) ->
	spawn_link(?MODULE, init, [{Mod, Args}]).

%%% Function called by spawned processes
init({Mod,Args}) ->
	%% *Make all exit messages be received as ordinary messages
	process_flag(trap_exit, true),

	%% Call loop function to have it start a new process for Mod and start_link with Args
	loop({Mod, start_link, Args}).

loop({M,F,A}) ->
	%% Call the module, function, passing in the Arguments
	Pid = apply(M,F,A),

	%% Receive messages
	receive
		%% When receiving a shutdown message, shutdown
		{'EXIT', _From, shutdown} ->
			exit(shutdown); % will kill the child too
		%% For other exit messages show reason and continue
		{'EXIT', Pid, Reason} ->
			io:format("Process ~p exited for reason ~p~n", [Pid,Reason]),
			loop({M,F,A})
	end.

