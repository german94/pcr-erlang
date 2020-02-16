-module(pcr_consume).
-export([consume_setup/2]).

consume_setup(Component, InternalToken) ->
    Listeners = receive_listeners(),
    Inputs = case is_producer_or_pcr(Component) of
        true -> [receive_producer_input()];
        false -> receive_consumer_inputs(Component, [])
    end,
    consume(Component, Listeners, Inputs, InternalToken).

receive_listeners() ->
    receive
        {listeners, Listeners} ->
            erlang:display({consumer_received_listeners, Listeners}),
            Listeners
    end.

is_producer_or_pcr(Component) ->
    (pcr_components:is_producer(Component) == true) or (pcr_components:is_pcr(Component) == true).

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

consume(Component, Listeners, Inputs, InternalToken) ->
    case pcr_components:is_pcr(Component) of
        true -> nested_pcr_consume(Component, Listeners, Inputs, InternalToken);
        false -> naive_consume(Component, Listeners, Inputs, InternalToken)
    end.

nested_pcr_consume(Consumer, Listeners, Input, InternalToken) ->
    Pcr = pcr_init:start_pcr(pcr_components:get_pcr(Consumer), [self()]),
    erlang:display({sending_input_to_nested_consumer_pcr, Input}),
    pcr_utils:send_input_to_pcr(Input, Pcr),
    receive 
        {pcr_output, ConsumerOutput} ->
            erlang:display({broadcasting_output_to_listeners, ConsumerOutput, Listeners}),
            pcr_utils:broadcast_to_nodes({output, pcr_components:get_id(Consumer), ConsumerOutput, InternalToken}, Listeners)
    end,
    erlang:display({stopping_nested_consumer_pcr, Pcr}),
    pcr_utils:stop_pcr(Pcr).

naive_consume(Consumer, Listeners, Inputs, InternalToken) ->
    erlang:display({applying_fun_to, Inputs}),
    ConsumerFunction = pcr_components:get_fun(Consumer),
    ConsumerOutput = case pcr_components:is_producer(Consumer) of
        true -> apply(ConsumerFunction, Inputs);
        false -> pcr_utils:apply_fun(ConsumerFunction, pcr_components:get_sources(Consumer), Inputs)
    end,
    erlang:display({broadcasting_output_to_listeners, ConsumerOutput, Listeners}),
    pcr_utils:broadcast_to_nodes({output, pcr_components:get_id(Consumer), ConsumerOutput, InternalToken}, Listeners).