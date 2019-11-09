-module(pcr).
-export([start_pcr/2, output_loop/1, production_loop/3, reduce_loop/5, consume/2, produce/2, pcr_sequential_composition/3]).
-record(reducer, {function, initial_val}).
-record(pcr, {producer, consumers, reducer}).

%PCR record getters
get_reducer_fun(Pcr) ->
    Pcr#pcr.reducer#reducer.function.

get_reducer_initial_value(Pcr) ->
    Pcr#pcr.reducer#reducer.initial_val.

get_consumers(Pcr) ->
    Pcr#pcr.consumers.

get_producer(Pcr) ->
    Pcr#pcr.producer.

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

%Starts producer, consumers and reducers for each new input
production_loop(Pcr, OutputLoopPid, ExternalListenerPids) ->
    receive
        {input, Input} ->
            Token = generate_uuid(),
            OutputLoopPid ! {new_item, Token},
            Consumers = get_consumers(Pcr),
            ReducerPid = spawn_reducer(Pcr, length(Consumers), OutputLoopPid, Token),
            ConsumerPids = spawn_consumers(Pcr, ReducerPid),
            ProducerPid = spawn_producer(Pcr, ConsumerPids),
            produce_new_item(ProducerPid, Input),
            erlang:display({new_input, Input, Token}),
            production_loop(Pcr, OutputLoopPid, ExternalListenerPids);
        stop ->
            OutputLoopPid ! stop        %here we should kill all the other PCR processes: they should be linked to this one
    end.

%Spawns the reduce loop for a particular input (identified by the token token) and returns the PID
spawn_reducer(Pcr, NumberOfItemsToReduce, OutputLoopPid, Token) ->
    spawn(
        pcr,
        reduce_loop, 
        [get_reducer_fun(Pcr), get_reducer_initial_value(Pcr), NumberOfItemsToReduce, OutputLoopPid, Token]).

%Spawns the list of consumers and returns the PIDs
spawn_consumers(Pcr, ReducerPid) ->
    lists:map(fun(Consumer) -> spawn_consumer(Consumer, ReducerPid) end, get_consumers(Pcr)).

%Spawns a particular consumer and returns the PID
spawn_consumer(Consumer, ReducerPid) ->
    spawn_pcr_node(Consumer, consume, ReducerPid).

%Spawns the PCR producer and returns the PID
spawn_producer(Pcr, ConsumerPids) ->
    spawn_pcr_node(get_producer(Pcr), produce, ConsumerPids).

%Spawn a PCR node, it could be a nested PCR or a basic function (only producers and consumers are supported)
%Returns the PID of the new node
spawn_pcr_node(Node, BasicFunctionApplier, ExternalListenerPids) ->
    if
        is_function(Node) ->
            spawn(pcr, BasicFunctionApplier, [Node, ExternalListenerPids]);
        true ->
            start_pcr(Node, ExternalListenerPids)
    end.

%Sends the produce message with the corresponding input to the producer process.
%Producer processes, like consumer ones, process one input in their entire lifecycle so it also sends the stop signal.
produce_new_item(ProducerPid, Input) ->
    ProducerPid ! {input, Input},
    ProducerPid ! stop.

%Applies the produce function and sends the output to all the consumers
produce(ProduceFun, ConsumerPids) ->
    receive
        {input, Input} ->
            ProducedItem = ProduceFun(Input),
            lists:foreach(
                fun(CPid) -> CPid ! {input, ProducedItem}, CPid ! stop end,
                ConsumerPids)
    end.

%Applies the consume function and sends the output to the producer
consume(ConsumeFun, ReducerPid) ->
    receive
        {input, ProducedItem} ->
            ConsumerOutput = ConsumeFun(ProducedItem),
            erlang:display({new_input_consumed, ProducedItem, ConsumerOutput}),
            ReducerPid ! {consumer_output, ConsumerOutput}
    end.

%Applies the reduction function until all elements are reduced.
%When there are no more elements the output is sent to the OutputLoop process with the corresponding token
reduce_loop(_, ReducedItem, 0, OutputLoopPid, Token) -> 
    OutputLoopPid ! {reduced, Token, ReducedItem};
reduce_loop(ReduceFun, AccVal, NumberOfItemsToReduce, OutputLoopPid, Token) ->
    receive
        {consumer_output, Input} ->
            ReducedVal = ReduceFun(AccVal, Input),
            erlang:display({new_reduction, Input, ReducedVal}),
            reduce_loop(ReduceFun, ReducedVal, NumberOfItemsToReduce - 1, OutputLoopPid, Token)
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