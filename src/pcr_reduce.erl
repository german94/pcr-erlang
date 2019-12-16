-module(pcr_reduce).
-export([reduce/4]).

reduce(Pcr, NumberOfItemsToReduce, OutputLoopPid, ExternalToken) ->
    Reducer = pcr_components:get_reducer(Pcr),
    ReducerInitialValue = pcr_components:get_reducer_initial_value(Reducer),
    reduce_loop(
        Reducer,
        ReducerInitialValue, 
        NumberOfItemsToReduce, 
        OutputLoopPid,
        ExternalToken,
        maps:new()
    ).

%Applies the reduction function until all elements are reduced.
%When there are no more elements the output is sent to the OutputLoop process with the corresponding token
reduce_loop(_, FullReduction, 0, OutputLoopPid, ExternalToken, _) ->
    erlang:display({reduced, ExternalToken, FullReduction}),
    OutputLoopPid ! {reduced, ExternalToken, FullReduction};
    
reduce_loop(Reducer, AccVal, NumberOfItemsToReduce, OutputLoopPid, ExternalToken, PartialParametersLists) ->
    receive
        {output, Id, Input, InternalToken} ->
            erlang:display({reducing, Id, Input, InternalToken}),
            NewReductions = maps:put(
                InternalToken,
                [{Id, Input} | maps:get(InternalToken, PartialParametersLists, [])],
                PartialParametersLists
            ),
            PartialParametersList = maps:get(InternalToken, NewReductions),
            Sources = pcr_components:get_sources(Reducer),
            if
                length(PartialParametersList) == length(Sources) ->
                    ReducedVal = pcr_utils:apply_fun(pcr_components:get_fun(Reducer), Sources, [AccVal | PartialParametersList]),
                    erlang:display({new_reduction, Input, ReducedVal}),
                    reduce_loop(Reducer, ReducedVal, NumberOfItemsToReduce - 1, OutputLoopPid, ExternalToken, PartialParametersLists);
                true ->
                    reduce_loop(Reducer, AccVal, NumberOfItemsToReduce, OutputLoopPid, ExternalToken, PartialParametersList)
            end
    end.