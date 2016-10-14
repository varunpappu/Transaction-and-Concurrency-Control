%% Varun Subramanian
%% - Server module
%% - The server module creates a parallel registered process by spawning a process which
%% evaluates initialize().
%% The function initialize() does the following:
%%      1/ It makes the current process as a system process in order to trap exit.
%%      2/ It creates a process evaluating the store_loop() function.
%%      4/ It executes the server_loop() function.

-module(server).

-export([start/0]).

%%%%%%%%%%%%%%%%%%%%%%% STARTING SERVER %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
start() ->
    register(transaction_server, spawn(fun() ->
                                               process_flag(trap_exit, true),
                                               Val= (catch initialize()),
                                               io:format("Server terminated with:~p~n",[Val])
                                       end)).

initialize() ->
    process_flag(trap_exit, true),
    Initialvals = [{a,0},{b,0},{c,0},{d,0}], %% All variables are set to 0
    ServerPid = self(),
    TimeStamp = get_timestamp(),
    StorePid = spawn_link(fun() -> store_loop(ServerPid,Initialvals,TimeStamp,[]) end),
    server_loop([],StorePid).

%%We assign a timestamp function
get_timestamp()->
    {Mega, Sec, Micro}=erlang:now(),
    (Mega*1000+Sec)*1000+Micro.

%%%%%%%%%%%%%%%%%%%%%%% STARTING SERVER %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


%%%%%%%%%%%%%%%%%%%%%%% ACTIVE SERVER %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% - The server maintains a list of all connected clients and a store holding
%% the values of the global variable a, b, c and d

server_loop(ClientList, StorePid) ->
    receive
        {login, MM, Client} ->
            MM ! {ok, self()},
            io:format("New client has joined the server:~p.~n", [Client]),
            StorePid ! {print, self()},
            server_loop(add_client(Client, ClientList), StorePid);
        {close, Client} ->
            io:format("Client~p has left the server.~n", [Client]),
            StorePid ! {print, self()},
            server_loop(remove_client(Client, ClientList), StorePid);
        {request, Client} ->
            Client ! {proceed, self()},
            server_loop(ClientList, StorePid);
        {confirm, Client} ->
            StorePid!{req, Client},  %%all requested items are sent to the server
            Client ! {abort, self()},
            server_loop(ClientList, StorePid);
        {action, Client, Act} ->
            io:format("Received~p from client~p.~n", [Act, Client]),
            io:format("Server starts to send! ~n"),
            StorePid!{action,Client, Act},
            io:format("Request sent by the server! ~n"),
            server_loop(ClientList, StorePid);
        {result, Result, Client}->
            Client!{result, Result},
            server_loop(ClientList, StorePid)
    after 50000 ->
            case all_gone(ClientList) of
                true -> exit(normal);
                false -> server_loop(ClientList,StorePid)
            end
    end.

%%Concurrency Control%%
updates(Database, [])->
    Database;
updates(Database, [{Variable, Value} | Actions])->
    case lists:keyfind(Variable, 1, Database) of        %%update the values
        false->
            NewDatabase = Database ++ [{Variable, Value}];
            _ ->
            NewDatabase = lists:keyreplace(Variable, 1, Database, {Variable, Value})
        end,
    updates(NewDatabase, Actions).
concurrency(StorePid, Database, Version, Client, ActionList)->
    receive
        {value_req, Variable, Pid}->
            {_, Value} = lists:keyfind(Variable, 1, Database),
            Pid!{answer, Value},
            concurrency(StorePid, Database, Version, Client, ActionList);
        {write, Variable, NewValue}->
            io:format("New write request received ~n"),
            case lists:keyfind(Variable, 1, Database) of
                false->
                    NewDatabase = Database++ [{Variable, NewValue}];
                    _ ->
                    NewDatabase = lists:keyreplace
                                    (Variable, 1, Database, {Variable, NewValue})
            end,
            concurrency(StorePid, NewDatabase, Version, Client, ActionList ++
                            [{Variable, NewValue}]);
        {abort, NewDatabase, NewVersion}->
            LatestData=updates(NewDatabase, ActionList),
            StorePid!{writeResult, LatestData, NewVersion, Client, self()},
            concurrency(StorePid, LatestData, NewVersion, Client, ActionList);
        {req} ->
            StorePid!{writeResult, Database, Version, Client, self()},   %%communication received
            receive
                {updataConfirm}->
                    exit("updated");
                {abort, NewDatabase, NewVersion} ->
                    LatestData = updates(NewDatabase, ActionList),
                    StorePid!{writeResult, LatestData, NewVersion, Client, self()},
                    concurrency(StorePid, LatestData, NewVersion, Client, ActionList)
            end
    end.
con_control(StorePid, Database, Variable, NewValue, Version, Client)->
    case lists:keyfind(Variable, 1, Database) of
        false->
            NewDatabase = Database ++ [{Variable, NewValue}];
        _ ->
            NewDatabase = lists:keyreplace(Variable, 1, Database, {Variable, NewValue})
    end,
    concurrency(StorePid, NewDatabase, Version, Client, [{Variable, NewValue}]).  %%update performed

store_loop(ServerPid, Database, Version, TentativeThreads) ->   %% We store the values here
    receive
        {print, ServerPid} ->
            io:format("Database status:~n~p.~n",[Database]),
            store_loop(ServerPid,Database, Version, TentativeThreads);
        {req, Client}->
            case lists:keyfind(Client, 1, TentativeThreads) of
                false->
                    store_loop(ServerPid, Database, Version, TentativeThreads);
                {_, ThreadPid}->
                    ThreadPid!{req},    %%Communication is being performed%%
                    store_loop(ServerPid, Database, Version, TentativeThreads)
            end;
        {action, Client, Act}->
            case Act of
                {read, Variable} ->
                    io:format("server has received read request! ~n"),
                    case lists:keyfind(Client, 1, TentativeThreads) of
                        false->
                            case lists:keyfind(Variable, 1, Database) of
                                false->
                                    ServerPid!{result, fail, Client};
                                {_, Value} ->
                                    ServerPid!{result, Value, Client}
                            end;
                        {_, ThreadPid}->
                            ThreadPid!{value_req, Variable, self()},
                            receive
                                {answer, Value}->
                                    ServerPid!{result, Value, Client}
                            after 5000->
                                    ServerPid!{result, fail, Client}
                            end
                    end,
                    store_loop(ServerPid,Database,Version,TentativeThreads);
                {write, Variable, NewValue} ->
                    io:format("server has received write request! ~n"),
                    case lists:keyfind(Client, 1, TentativeThreads) of
                        false->
                            Thread=self(),   %% create new thread to handle this %%
                            ThreadPid = spawn(fun ()->
                                                      (con_control(Thread, Database,
                                                                   Variable,
                                                                   NewValue, Version,
                                                                   Client)) end),
                            store_loop(ServerPid, Database, Version,
                                       TentativeThreads++[{Client, ThreadPid}]);
                        {_, ThreadPid}->
                            ThreadPid!{write, Variable, NewValue},
                            store_loop(ServerPid, Database, Version, TentativeThreads)
                    end
            end;

        %%Concurrency Control
        {writeResult, NewDatabase, OldVersion, Client, ThreadPid} ->
            case OldVersion==Version of
                true->
                    ThreadPid!{updateConfirm},
                    io:format("update confirmed ~n~p", [NewDatabase]),
                    NewTentativeThreads=lists:keydelete(Client, 1, TentativeThreads),
                    ServerPid!{result, writeSuccess, Client},
                    store_loop(ServerPid, NewDatabase, get_timestamp(), NewTentativeThreads);
                _ ->
                    io:format("Stop update ~n"),
                    ThreadPid!{abort, Database, Version},
                    store_loop(ServerPid, Database, Version, TentativeThreads)
            end
    end.
%%%%%%%%%%%%%%%%%%%%%%% ACTIVE SERVER %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% - Low level function to handle lists
add_client(C,T) -> [C|T].

remove_client(_,[]) -> [];
remove_client(C, [C|T]) -> T;
remove_client(C, [H|T]) -> [H|remove_client(C,T)].

all_gone([]) -> true;
all_gone(_) -> false.
