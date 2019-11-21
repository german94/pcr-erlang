-module(pcr).
-export([start_pcr/2, pcr_sequential_composition/3, send_pcr_input/2]).
-export([
    apply_fun/3, 
    production_loop/3, 
    stop_pcr/1, 
    notify_new_item/2, 
    spawn_reducer/4,
    spawn_pcr/3,
    spawn_consumer/2,
    spawn_pcr_node/3,
    get_producer_listeners/2,
    send_message_to_node/2,
    broadcast_to_nodes/2,
    send_receivers_data_to_nodes/2,
    produce_new_value/3,
    start_producer/4,
    produce_new_set_of_values/3,
    consume/4,
    consume_setup/2,
    reduce_loop/7,
    output_loop/1,
    wait_for_output/1,
    generate_uuid/0,
    send_pcr_input/2]).

apply_fun(Fun, [], Inputs) ->
    apply(Fun, Inputs);
apply_fun(Fun, [Source|Sources], Inputs) ->
    InputOfSource = element(2, lists:keyfind(Source, 1, Inputs)),
    apply_fun(Fun, Sources, [InputOfSource|lists:keydelete(Source, 1, Inputs)]).

%External inputs get into Pcr1, then Pcr1 output becomes the input for PCR2
%and finally the output of the whole composition is the output of Pcr2
pcr_sequential_composition(Pcr1, Pcr2, ExternalListenerPids) ->
    Pcr2Pid = start_pcr(Pcr2, ExternalListenerPids),
    start_pcr(Pcr1, Pcr2Pid).

%Starts the PCR and returns its PID.
%ExternalListenerPids is a list of all the processes who want to know the PCR outputs.
%PCR output format is the following: {pcr_output, Output}
start_pcr(Pcr, ExternalListenerPids) ->
    OutputLoopPid = spawn(pcr, output_loop, [ExternalListenerPids]),
    spawn(pcr, production_loop, [Pcr, OutputLoopPid, ExternalListenerPids]).

%Listens for new PCR inputs and for each one it signals the OutputLoop process to wait for the new output,
%spawns the reducer and produces the new set of values corresponding to the input
production_loop(Pcr, OutputLoopPid, ExternalListenerPids) ->
    receive
        {input, Input} ->
            Token = generate_uuid(),        %this token is used to match PCR inputs with PCR outputs
            notify_new_item(OutputLoopPid, Token),
            erlang:display({new_input, Input, Token}),
            ReducerPid = spawn_reducer(Pcr, Input + 1, OutputLoopPid, Token),
            produce_new_set_of_values(Pcr, Input, ReducerPid),
            production_loop(Pcr, OutputLoopPid, ExternalListenerPids);
        stop ->
            stop_pcr(OutputLoopPid)        %here we should kill all the other PCR processes: they should be linked to the one that runs this function
    end.

stop_pcr(OutputLoopPid) ->
    OutputLoopPid ! stop.

send_pcr_input(Input, PcrPid) ->
    PcrPid ! {input, Input}.

notify_new_item(OutputLoopPid, Token) ->
    OutputLoopPid ! {new_item, Token}.

%Spawns the reduce loop for a particular external input (identified by the token) and returns the PID
spawn_reducer(Pcr, NumberOfItemsToReduce, OutputLoopPid, Token) ->
    spawn(
        pcr,
        reduce_loop, 
        [
            pcr_components:get_reducer(Pcr), 
            pcr_components:get_reducer_initial_value(Pcr),
            NumberOfItemsToReduce,
            length(pcr_components:get_sources(pcr_components:get_reducer(Pcr))),
            OutputLoopPid,
            Token,
            maps:new()
        ]).

%Spawns all the pcr nodes but the producer one
spawn_pcr(Pcr, ReducerPid, InternalToken) ->
    Consumers = [pcr_nodes:create_node(pcr_components:get_id(Consumer), spawn_consumer(Consumer, InternalToken)) || Consumer <- pcr_components:get_consumers(Pcr)],
    Reducer = pcr_nodes:create_node(pcr_components:get_reducer_id(Pcr), ReducerPid),
    [Reducer | Consumers].

%Spawns a particular consumer and returns the PID
spawn_consumer(Consumer, InternalToken) ->    %consumer_logic should work for both consumer and producer records
    spawn(pcr, consume_setup, [Consumer, InternalToken]).     %CAREFUL! the consumer logic can be a nested PCR!!!!!!

%Spawn a PCR node, it could be a nested PCR or a basic function (only producers and consumers are supported)
%Returns the PID of the new node
spawn_pcr_node(Node, BasicFunctionApplier, ExternalListenerPids) ->
    if
        is_function(Node) ->
            spawn(pcr, BasicFunctionApplier, [Node, ExternalListenerPids]);
        true ->
            start_pcr(Node, ExternalListenerPids)
    end.

get_producer_listeners(Pcr, Listeners) ->
    [Listener || Listener <- Listeners, lists:is_member(pcr_components:get_id(pcr_components:get_producer(Pcr)), pcr_components:get_listeners_of_id(pcr_nodes:get_node_id(Listener), Pcr))].

send_message_to_node(Message, Node) ->
    pcr_nodes:get_node_pid(Node) ! Message.

broadcast_to_nodes(Message, Nodes) ->
    lists:foreach(fun(Node) -> send_message_to_node(Message, Node) end, Nodes).

send_receivers_data_to_nodes(Pcr, Listeners) ->
    lists:foreach(
        fun(Listener) -> send_message_to_node({listener_pids, pcr_components:get_listeners_of_id(pcr_nodes:get_node_id(Listener), Pcr)}, Listener) end,
        Listeners).

%Spawns both producer and consumers and sends the producer the signal to generate the new value
produce_new_value(Pcr, Input, ReducerPid) ->
    InternalToken = generate_uuid(),     %this token is used to identify produced items associated to a single PCR external input
    Listeners = spawn_pcr(Pcr, ReducerPid, InternalToken), 
    send_receivers_data_to_nodes(Pcr, Listeners),  %sends a {listeners_pids, Listeners} message to each node so everyone knows who to send the output
    start_producer(Pcr, Listeners, Input, InternalToken).

start_producer(Pcr, Listeners, Input, InternalToken) ->
    ProducerPid = spawn_consumer(pcr_components:get_producer(Pcr), InternalToken),
    ProducerPid ! {listeners_pids, get_producer_listeners(Pcr, Listeners)},
    ProducerPid ! {input, Input},
    ProducerPid ! stop.

%Iterates the produce function producing the values concurrently
produce_new_set_of_values(Pcr, Input, ReducerPid) ->
    lists:foreach(fun(Index) -> produce_new_value(Pcr, Index, ReducerPid) end, lists:seq(0, Input)).

%Applies the consume function and sends the output to the producer
consume(Consumer, Listeners, Inputs, InternalToken) ->
    case length(Inputs) == pcr_components:get_sources(Consumer) of
        true ->
            ConsumerOutput = apply_fun(pcr_components:get_fun(Consumer), pcr_components:get_sources(Consumer), Inputs),
            broadcast_to_nodes([{output, pcr_components:get_id(Consumer), ConsumerOutput, InternalToken}], Listeners);
        false -> 
            receive
                {output, Id, Input, _} ->
                    consume(Consumer, Listeners, [{Id, Input} | Inputs], InternalToken)
            end
    end.

consume_setup(Consumer, InternalToken) ->
    receive
        {listeners_pids, Listeners} ->
            consume(Consumer, Listeners, [], InternalToken)
    end.

%Applies the reduction function until all elements are reduced.
%When there are no more elements the output is sent to the OutputLoop process with the corresponding token
reduce_loop(_, FullReduction, 0, _, OutputLoopPid, ExternalToken, _) -> 
    OutputLoopPid ! {reduced, ExternalToken, FullReduction};
reduce_loop(Reducer, AccVal, NumberOfItemsToReduce, NumberOfSources, OutputLoopPid, ExternalToken, PartialParametersLists) ->
    receive
        {output, Id, Input, InternalToken} ->
            NewReductions = maps:put(InternalToken, [{Id, Input} | maps:get(InternalToken, [], PartialParametersLists)]),
            PartialParametersList = maps:get(InternalToken, NewReductions),
            if
                length(PartialParametersList) == NumberOfSources ->
                    ReducedVal = apply_fun(pcr_components:get_fun(Reducer), pcr_components:get_sources(Reducer), [AccVal | PartialParametersList]),
                    erlang:display({new_reduction, Input, ReducedVal}),
                    reduce_loop(Reducer, ReducedVal, NumberOfItemsToReduce - 1, NumberOfSources, OutputLoopPid, ExternalToken, PartialParametersLists);
                true ->
                    reduce_loop(Reducer, AccVal, NumberOfItemsToReduce, NumberOfSources, OutputLoopPid, ExternalToken, PartialParametersList)
            end
    end.

%Receives a signal of a new element that got into the PCR, waits for the PCR output for that element and sends
%it to all the external listeners
output_loop(ExternalListenerPids) ->
    receive
        {new_item, Token} ->
            PcrOutput = wait_for_output(Token),
            erlang:display({sending_output_to_listeners, PcrOutput}),
            SendOutputFunction = fun(Pid) -> Pid ! {pcr_output, PcrOutput} end,
            lists:foreach(SendOutputFunction, ExternalListenerPids),
            output_loop(ExternalListenerPids);
        stop -> exit(0)
    end.

%Waits (blocks) for a particular (token) PCR output
wait_for_output(Token) ->
    erlang:display("Waiting for token " ++ Token),
    receive
        {reduced, Token, Item} ->
            erlang:display({token_received, Token, Item}),
            Item
    end.

%Generates a new token with a length of 20 characters
generate_uuid() ->
    base64:encode(crypto:strong_rand_bytes(20)).

%Encapsulates the message that is sent to the PCR with the input
send_input_to_pcr(PcrPid, Input) ->
    PcrPid ! {input, Input}.