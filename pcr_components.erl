-module(pcr_components_interface).
-record(consumer, {id, sources, node_logic}).
-record(producer, {id, node_logic}).
-record(reducer, {id, sources, node_logic, initial_val}).
-record(pcr, {producer, consumers, reducer}).
-export([
    get_reducer_initial_value/1, 
    get_reducer_id/1,
    get_consumers/1,
    get_producer/1,
    get_reducer/1,
    get_consumers_of/2,
    get_listeners_of_id/2,
    get_id/1,
    get_sources/1,
    get_fun/1
]).

get_reducer_initial_value(Pcr) ->
    Pcr#pcr.reducer#reducer.initial_val.

get_reducer_id(Node) ->
    if
        is_record(Node, reducer) -> Node#reducer.id;
        true -> get_reducer_id(get_reducer(Node))
    end.

get_consumers(Pcr) ->
    Pcr#pcr.consumers.

get_producer(Pcr) ->
    Pcr#pcr.producer.

get_reducer(Pcr) ->
    Pcr#pcr.reducer.

get_consumers_of(Id, Pcr) ->
    [Consumer || Consumer <- get_consumers(Pcr), lists:member(Id, get_sources(Consumer))].

get_listeners_of_id(Id, Pcr) ->
    ConsumersListeners = get_consumers_of(Id, Pcr),
    Reducer = get_reducer(Pcr),
    case lists:member(Id, get_sources(Reducer)) of
        true -> [Reducer | ConsumersListeners];
        false -> ConsumersListeners
    end.

get_id(Component) when element(1, Component) == consumer -> Component#consumer.id;
get_id(Component) when element(1, Component) == producer -> Component#producer.id;
get_id(Component) when element(1, Component) == reducer -> Component#reducer.id.

get_sources(Component) when element(1, Component) == consumer -> Component#consumer.sources;
get_sources(Component) when element(1, Component) == reducer -> Component#reducer.sources.

get_fun(Component) when element(1, Component) == consumer -> Component#consumer.node_logic;
get_fun(Component) when element(1, Component) == producer -> Component#producer.node_logic;
get_fun(Component) when element(1, Component) == reducer -> Component#reducer.node_logic.