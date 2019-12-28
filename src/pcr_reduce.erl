-module(pcr_reduce).
-record(reduction, {reducer, reduced_value, number_of_items_to_reduce, params_from_sources, token, output_pid}).
-export([reduce/4]).

reduce(Pcr, NumberOfItemsToReduce, OutputLoopPid, ExternalToken) ->
    Reducer = pcr_components:get_reducer(Pcr),
    InitialReduction = #reduction{
        reducer = Reducer,
        reduced_value = pcr_components:get_reducer_initial_value(Reducer),
        number_of_items_to_reduce = NumberOfItemsToReduce,
        params_from_sources = maps:new(),
        token = ExternalToken,
        output_pid = OutputLoopPid
    },
    reduce_loop(InitialReduction).

reduce_loop(
        #reduction{
            reducer=_,
            reduced_value=FullReduction, 
            number_of_items_to_reduce=0, 
            params_from_sources=_, 
            token=ExternalToken,
            output_pid=OutputLoopPid
        }) ->
    erlang:display({reduced, ExternalToken, FullReduction}),
    OutputLoopPid ! {reduced, ExternalToken, FullReduction};

reduce_loop(Reduction) ->
    receive
        {output, SourceId, SourceValue, ProducedValueToken} ->
            erlang:display({reducing, SourceId, SourceValue, ProducedValueToken}),

            SourceValueForMap = generate_source_value_for_map(SourceId, SourceValue),
            UpdatedReduction = generate_new_reduction(ProducedValueToken, Reduction, SourceValueForMap),

            do_reduce(ProducedValueToken, UpdatedReduction)
    end.

generate_source_value_for_map(SourceId, SourceValue) ->
    {SourceId, SourceValue}.

generate_new_reduction(ProducedValueToken, CurrentReduction, SourceValueForMap) ->
    SourcesMap = CurrentReduction#reduction.params_from_sources,
    UpdatedSourcesMap = generate_new_sources_map(ProducedValueToken, SourceValueForMap, SourcesMap),
    CurrentReduction#reduction{params_from_sources = UpdatedSourcesMap}.

do_reduce(ProducedValueToken, Reduction) ->
    case enough_sources_for_value(ProducedValueToken, Reduction) of
        true ->
            reduce_value(ProducedValueToken, Reduction);
        false ->
            reduce_loop(Reduction)
    end.

generate_new_sources_map(ProducedValueToken, SourceValue, SourcesMap) ->
    OtherSourcesValues = maps:get(ProducedValueToken, SourcesMap, []),
    FinalValue = [SourceValue|OtherSourcesValues],
    maps:put(ProducedValueToken, FinalValue, SourcesMap).

enough_sources_for_value(ProducedValueToken, Reduction) ->
    SourcesOutputsForInputValue = maps:get(ProducedValueToken, Reduction#reduction.params_from_sources),
    Reducer = Reduction#reduction.reducer,
    length(SourcesOutputsForInputValue) == length(pcr_components:get_sources(Reducer)).

reduce_value(ProducedValueToken, Reduction) ->
    NewReducedVal = apply_reduce_function(ProducedValueToken, Reduction),
    erlang:display({new_reduction, NewReducedVal}),
    UpdatedReduction = update_reduction(Reduction, NewReducedVal),
    reduce_loop(UpdatedReduction).

apply_reduce_function(ProducedValueToken, Reduction) ->
    Reducer = Reduction#reduction.reducer,
    Parameters = generate_reduction_parameters_for_value(ProducedValueToken, Reduction),
    ReduceFunction = pcr_components:get_fun(Reducer),
    Sources = pcr_components:get_sources(Reducer),
    pcr_utils:apply_fun(ReduceFunction, Sources, Parameters).

update_reduction(Reduction, NewReducedVal) ->
    DecrementedNumberOfItems = Reduction#reduction.number_of_items_to_reduce - 1,
    Reduction#reduction{reduced_value=NewReducedVal, number_of_items_to_reduce=DecrementedNumberOfItems}.

generate_reduction_parameters_for_value(ProducedValueToken, Reduction) ->
    ReducedValueUntilNow = Reduction#reduction.reduced_value,
    ParamsFromSources = Reduction#reduction.params_from_sources,
    [ReducedValueUntilNow|maps:get(ProducedValueToken, ParamsFromSources)].