-module(pcr_consume).
-export([consume_setup/2]).

%Applies the consume function and sends the output to the producer
consume(Consumer, Listeners, Inputs, InternalToken) ->
    erlang:display({applying_fun_to, Inputs}),
    ConsumerFunction = pcr_components:get_fun(Consumer),
    ConsumerOutput = case pcr_components:is_producer(Consumer) of
        true -> apply(ConsumerFunction, Inputs);
        false -> pcr_utils:apply_fun(ConsumerFunction, pcr_components:get_sources(Consumer), Inputs)
    end,
    erlang:display({broadcasting_output_to_listeners, ConsumerOutput, Listeners}),
    pcr_utils:broadcast_to_nodes({output, pcr_components:get_id(Consumer), ConsumerOutput, InternalToken}, Listeners).

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