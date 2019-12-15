-module(pcr_init).
-export([start_pcr/2]).

%Starts the PCR and returns its PID.
%ExternalListenerPids is a list of all the processes who want to know the PCR outputs.
%PCR output format is the following: {pcr_output, Output}
start_pcr(Pcr, ExternalListenerPids) ->
    OutputLoopPid = spawn(pcr_output_handler, output_loop, [ExternalListenerPids]),
    spawn(fun() -> production_loop(Pcr, OutputLoopPid, ExternalListenerPids) end).

%Listens for new PCR inputs and for each one it signals the OutputLoop process to wait for the new output,
%spawns the reducer and produces the new set of values corresponding to the input
production_loop(Pcr, OutputLoopPid, ExternalListenerPids) ->
    erlang:display('Waiting for inputs...'),
    receive
        {input, Input} ->
            erlang:display('New input received'),
            Token = pcr_utils:generate_uuid(),        %this token is used to match PCR inputs with PCR outputs
            pcr_utils:notify_new_item(OutputLoopPid, Token),
            erlang:display({new_input, Input, Token}),
            ReducerPid = spawn_reducer(Pcr, Input + 1, OutputLoopPid, Token),
            produce_new_set_of_values(Pcr, Input, ReducerPid),
            production_loop(Pcr, OutputLoopPid, ExternalListenerPids);
        stop ->
            pcr_utils:stop_pcr(OutputLoopPid)        %here we should kill all the other PCR processes: they should be linked to the one that runs this function
    end.

%Spawns the reduce loop for a particular external input (identified by the token) and returns the PID
spawn_reducer(Pcr, NumberOfItemsToReduce, OutputLoopPid, Token) ->
    ReducerPid = spawn(
        pcr_reduce,
        reduce_loop, 
        [
            pcr_components:get_reducer(Pcr), 
            pcr_components:get_reducer_initial_value(Pcr),
            NumberOfItemsToReduce,
            length(pcr_components:get_sources(pcr_components:get_reducer(Pcr))),
            OutputLoopPid,
            Token,
            maps:new()
        ]),
    erlang:display({reducer_spawned, ReducerPid}),
    ReducerPid.

%Iterates the produce function producing the values concurrently
produce_new_set_of_values(Pcr, Input, ReducerPid) ->
    erlang:display('Producing set of values'),
    lists:foreach(fun(Index) -> produce_new_value(Pcr, Index, ReducerPid) end, lists:seq(0, Input)).

%Spawns both producer and consumers and sends the producer the signal to generate the new value
produce_new_value(Pcr, Input, ReducerPid) ->
    InternalToken = pcr_utils:generate_uuid(),     %this token is used to identify produced items associated to a single PCR external input
    Listeners = spawn_pcr_nodes(Pcr, ReducerPid, InternalToken), 
    pcr_utils:send_each_node_its_listeners(Pcr, Listeners),  %sends a {listeners, Listeners} message to each node so everyone knows who to send the output
    start_producer(Pcr, Listeners, Input, InternalToken).

%Spawns all the pcr nodes but the producer one
spawn_pcr_nodes(Pcr, ReducerPid, InternalToken) ->
    Consumers = [pcr_nodes:create_node(pcr_components:get_id(Consumer), spawn_consumer(Consumer, InternalToken)) || Consumer <- pcr_components:get_consumers(Pcr)],
    Reducer = pcr_nodes:create_node(pcr_components:get_reducer_id(Pcr), ReducerPid),
    [Reducer | Consumers].

start_producer(Pcr, Listeners, Input, InternalToken) ->
    ProducerPid = spawn_consumer(pcr_components:get_producer(Pcr), InternalToken),
    ProducerPid ! {listeners, pcr_utils:get_producer_listeners(Pcr, Listeners)},
    ProducerPid ! {input, Input},
    ProducerPid ! stop.

%Spawns a particular consumer and returns the PID
spawn_consumer(Consumer, InternalToken) ->    %consumer_logic should work for both consumer and producer records
    spawn(pcr_consume, consume_setup, [Consumer, InternalToken]).     %CAREFUL! the consumer logic can be a nested PCR!!!!!!
