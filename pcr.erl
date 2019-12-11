-module(pcr).
-export([start_pcr/2, pcr_sequential_composition/3, send_input_to_pcr/2]).
-export([
    apply_fun/3, 
    production_loop/3, 
    stop_pcr/1, 
    notify_new_item/2, 
    spawn_reducer/4,
    spawn_pcr_nodes/3,
    spawn_consumer/2,
    spawn_pcr_node/3,
    get_producer_listeners/2,
    send_message_to_node/2,
    broadcast_to_nodes/2,
    send_each_node_its_listeners/2,
    produce_new_value/3,
    start_producer/4,
    produce_new_set_of_values/3,
    consume/4,
    consume_setup/2,
    reduce_loop/7,
    output_loop/1,
    wait_for_output/1,
    generate_uuid/0
]).

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
    erlang:display('Waiting for inputs...'),
    receive
        {input, Input} ->
            erlang:display('New input received'),
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

notify_new_item(OutputLoopPid, Token) ->
    OutputLoopPid ! {new_item, Token}.

%Spawns the reduce loop for a particular external input (identified by the token) and returns the PID
spawn_reducer(Pcr, NumberOfItemsToReduce, OutputLoopPid, Token) ->
    ReducerPid = spawn(
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
        ]),
    erlang:display({reducer_spawned, ReducerPid}),
    ReducerPid.

%Spawns all the pcr nodes but the producer one
spawn_pcr_nodes(Pcr, ReducerPid, InternalToken) ->
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
    ProducerId = pcr_components:get_id(pcr_components:get_producer(Pcr)),
    ProducerListenersIds = [pcr_components:get_id(Component) || Component <- pcr_components:get_listeners_of_id(ProducerId, Pcr)],
    [Listener || Listener <- Listeners, lists:member(pcr_nodes:get_node_id(Listener), ProducerListenersIds)].

send_message_to_node(Message, Node) ->
    pcr_nodes:get_node_pid(Node) ! Message.

broadcast_to_nodes(Message, Nodes) ->
    lists:foreach(fun(Node) -> send_message_to_node(Message, Node) end, Nodes).

send_each_node_its_listeners(Pcr, Listeners) ->
    SendListenersToNode = fun(Node) -> 
        NodeId = pcr_nodes:get_node_id(Node),
        ListenersIds = [pcr_components:get_id(Listener) || Listener <- pcr_components:get_listeners_of_id(NodeId, Pcr)],
        ListenersNodes = [Listener || Listener <- Listeners, lists:member(pcr_nodes:get_node_id(Listener), ListenersIds)],
        erlang:display({sending_listeners_to_node, NodeId, ListenersNodes}),
        send_message_to_node({listeners, ListenersNodes}, Node) 
    end,
    lists:foreach(SendListenersToNode, Listeners).

%Spawns both producer and consumers and sends the producer the signal to generate the new value
produce_new_value(Pcr, Input, ReducerPid) ->
    InternalToken = generate_uuid(),     %this token is used to identify produced items associated to a single PCR external input
    Listeners = spawn_pcr_nodes(Pcr, ReducerPid, InternalToken), 
    send_each_node_its_listeners(Pcr, Listeners),  %sends a {listeners, Listeners} message to each node so everyone knows who to send the output
    start_producer(Pcr, Listeners, Input, InternalToken).

start_producer(Pcr, Listeners, Input, InternalToken) ->
    ProducerPid = spawn_consumer(pcr_components:get_producer(Pcr), InternalToken),
    ProducerPid ! {listeners, get_producer_listeners(Pcr, Listeners)},
    ProducerPid ! {input, Input},
    ProducerPid ! stop.

%Iterates the produce function producing the values concurrently
produce_new_set_of_values(Pcr, Input, ReducerPid) ->
    erlang:display('Producing set of values'),
    lists:foreach(fun(Index) -> produce_new_value(Pcr, Index, ReducerPid) end, lists:seq(0, Input)).

%Applies the consume function and sends the output to the producer
consume(Consumer, Listeners, Inputs, InternalToken) ->
    erlang:display({applying_fun_to, Inputs}),
    ConsumerFunction = pcr_components:get_fun(Consumer),
    ConsumerOutput = case pcr_components:is_producer(Consumer) of
        true -> apply(ConsumerFunction, Inputs);
        false -> apply_fun(ConsumerFunction, pcr_components:get_sources(Consumer), Inputs)
    end,
    erlang:display({broadcasting_output_to_listeners, ConsumerOutput, Listeners}),
    broadcast_to_nodes({output, pcr_components:get_id(Consumer), ConsumerOutput, InternalToken}, Listeners).

receive_producer_input() ->
    receive
        {input, Input} ->
            Input
    end.

receive_consumer_inputs(Consumer, Inputs) ->
    case length(Inputs) == length(pcr_components:get_sources(Consumer)) of
        true -> Inputs;
        false -> 
            receive
                {output, Id, Input, _} ->
                    receive_consumer_inputs(Consumer, [{Id, Input} | Inputs])
                end
    end.

receive_listeners() ->
    receive
        {listeners, Listeners} ->
            erlang:display({consumer_received_listeners, Listeners}),
            Listeners
    end.

consume_setup(Consumer, InternalToken) ->
    Listeners = receive_listeners(),
    Inputs = case pcr_components:is_producer(Consumer) of
        true -> [receive_producer_input()];
        false -> receive_consumer_inputs(Consumer, [])
    end,
    consume(Consumer, Listeners, Inputs, InternalToken).
    

%Applies the reduction function until all elements are reduced.
%When there are no more elements the output is sent to the OutputLoop process with the corresponding token
reduce_loop(_, FullReduction, 0, _, OutputLoopPid, ExternalToken, _) ->
    erlang:display({reduced, ExternalToken, FullReduction}),
    OutputLoopPid ! {reduced, ExternalToken, FullReduction};
reduce_loop(Reducer, AccVal, NumberOfItemsToReduce, NumberOfSources, OutputLoopPid, ExternalToken, PartialParametersLists) ->
    receive
        {output, Id, Input, InternalToken} ->
            erlang:display({reducing, Id, Input, InternalToken}),
            NewReductions = maps:put(
                InternalToken,
                [{Id, Input} | maps:get(InternalToken, PartialParametersLists, [])],
                PartialParametersLists
            ),
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
    erlang:display('output_loop started'),
    receive
        {new_item, Token} ->
            erlang:display({new_item_notified, Token}),
            PcrOutput = wait_for_output(Token),
            erlang:display({sending_output_to_listeners, PcrOutput}),
            SendOutputFunction = fun(Pid) -> Pid ! {pcr_output, PcrOutput} end,
            erlang:display({sending_output, PcrOutput, ExternalListenerPids}),
            lists:foreach(SendOutputFunction, ExternalListenerPids),
            output_loop(ExternalListenerPids);
        stop -> exit(0)
    end.

%Waits (blocks) for a particular (token) PCR output
wait_for_output(Token) ->
    erlang:display({waiting_for_output, Token}),
    receive
        {reduced, Token, Item} ->
            erlang:display({token_received, Token, Item}),
            Item
    end.

%Generates a new token with a length of 20 characters
generate_uuid() ->
    base64:encode(crypto:strong_rand_bytes(20)).

%Encapsulates the message that is sent to the PCR with the input
send_input_to_pcr(Input, PcrPid) ->
    PcrPid ! {input, Input}.