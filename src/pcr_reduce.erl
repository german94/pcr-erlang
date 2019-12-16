-module(pcr_reduce).
-export([reduce_loop/7]).

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
                    ReducedVal = pcr_utils:apply_fun(pcr_components:get_fun(Reducer), pcr_components:get_sources(Reducer), [AccVal | PartialParametersList]),
                    erlang:display({new_reduction, Input, ReducedVal}),
                    reduce_loop(Reducer, ReducedVal, NumberOfItemsToReduce - 1, NumberOfSources, OutputLoopPid, ExternalToken, PartialParametersLists);
                true ->
                    reduce_loop(Reducer, AccVal, NumberOfItemsToReduce, NumberOfSources, OutputLoopPid, ExternalToken, PartialParametersList)
            end
    end.