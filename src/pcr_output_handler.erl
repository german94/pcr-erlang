-module(pcr_output_handler).
-export([output_loop/1]).

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